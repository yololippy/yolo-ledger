import CryptoKit
import Foundation
import SwiftData
import YoloLedgerCore

extension LedgerStoreActor {
    func fetchScheduledEntryRules() throws -> [LedgerScheduledEntryRule] {
        let records = try activeScheduledRuleVersionRecords()
        let currentRecords = Dictionary(grouping: records, by: \.ruleID).values.compactMap {
            $0.max(by: Self.isEarlierVersion)
        }
        return try currentRecords
            .map(Self.scheduledRule)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func saveScheduledEntryRuleVersion(
        _ rule: LedgerScheduledEntryRule
    ) throws -> LedgerScheduledEntryRule {
        do {
            let allRecords = try modelContext.fetch(
                FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>()
            )
            let sameRuleRecords = allRecords.filter { $0.ruleID == rule.id }
            if !sameRuleRecords.isEmpty,
               sameRuleRecords.allSatisfy({ $0.deletedAt != nil }) {
                throw LedgerScheduledEntryRepositoryError.ruleNotFound(rule.id)
            }
            try validateRuleReferences(rule)
            try replaceOrInsertRuleVersion(rule, records: allRecords)
            try modelContext.save()
            return rule
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func pauseScheduledEntryRule(
        id: UUID,
        effectiveMonth: LedgerYearMonth,
        updatedAt: Date
    ) throws -> LedgerScheduledEntryRule {
        try saveToggledRuleVersion(
            id: id,
            effectiveMonth: effectiveMonth,
            isEnabled: false,
            updatedAt: updatedAt
        )
    }

    func resumeScheduledEntryRule(
        id: UUID,
        effectiveStartMonth: LedgerYearMonth,
        updatedAt: Date
    ) throws -> LedgerScheduledEntryRule {
        try saveToggledRuleVersion(
            id: id,
            effectiveMonth: effectiveStartMonth,
            isEnabled: true,
            updatedAt: updatedAt
        )
    }

    func deleteScheduledEntryRule(id: UUID, deletedAt: Date) throws {
        guard deletedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LedgerScheduledEntryError.invalidDate
        }
        do {
            let records = try modelContext.fetch(
                FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>()
            ).filter { $0.ruleID == id && $0.deletedAt == nil }
            guard !records.isEmpty else {
                throw LedgerScheduledEntryRepositoryError.ruleNotFound(id)
            }
            for record in records { record.deletedAt = deletedAt }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func processDueScheduledEntries(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> LedgerScheduledProcessingResult {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw LedgerScheduledEntryError.invalidDate
        }
        do {
            let ruleRecords = try activeScheduledRuleVersionRecords()
            let occurrenceRecords = try modelContext.fetch(
                FetchDescriptor<LedgerSchemaV3.ScheduledOccurrenceRecord>()
            )
            let entryRecords = try modelContext.fetch(
                FetchDescriptor<LedgerSchemaV3.EntryRecord>()
            )
            var handledKeys = Set(occurrenceRecords.map(\.occurrenceKey))
            handledKeys.formUnion(entryRecords.compactMap(\.scheduledOccurrenceKey))
            var knownEntryIDs = Set(entryRecords.map(\.id))
            let currentMonth = try LedgerYearMonth.containing(
                now,
                calendar: calendar,
                timeZone: timeZone
            )
            let books = try activeScheduleBooks()
            let categories = try activeScheduleCategories()
            var generatedEntries: [LedgerEntry] = []
            var skippedOccurrenceCount = 0

            for records in Dictionary(grouping: ruleRecords, by: \.ruleID).values {
                let ordered = records.sorted(by: Self.isEarlierVersion)
                guard var month = try ordered.first.map(Self.effectiveMonth) else { continue }
                while month <= currentMonth {
                    guard let selected = try Self.applicableVersion(in: ordered, for: month) else {
                        month = try month.next()
                        continue
                    }
                    if selected.isEnabled {
                        let rule = try Self.scheduledRule(selected)
                        let scheduledDate = try LedgerScheduledEntryPlanner.scheduledDate(
                            for: rule.monthlyDay,
                            in: month,
                            calendar: calendar,
                            timeZone: timeZone
                        )
                        if scheduledDate <= now {
                            let metadata = LedgerScheduledOccurrenceMetadata(
                                ruleID: rule.id,
                                month: month
                            )
                            if handledKeys.contains(metadata.occurrenceKey) {
                                skippedOccurrenceCount += 1
                            } else {
                                let draft = LedgerEntryDraft(
                                    bookID: rule.bookID,
                                    categoryID: rule.categoryID,
                                    kind: rule.kind,
                                    amount: rule.amount,
                                    date: scheduledDate,
                                    note: rule.note,
                                    source: .scheduled,
                                    scheduledOccurrence: metadata
                                )
                                try LedgerValidation.validate(
                                    draft,
                                    books: books,
                                    categories: categories
                                )
                                let entryID = LedgerScheduledStorageIdentity.entryID(
                                    occurrenceKey: metadata.occurrenceKey
                                )
                                guard knownEntryIDs.insert(entryID).inserted else {
                                    throw LedgerStorageError.invalidStoredValue(
                                        entity: "定时账目",
                                        field: "稳定标识"
                                    )
                                }
                                let entryRecord = LedgerSchemaV3.EntryRecord(
                                    id: entryID,
                                    bookID: draft.bookID,
                                    categoryID: draft.categoryID,
                                    kindRawValue: draft.kind.rawValue,
                                    amountMinorUnits: draft.amount.minorUnits,
                                    occurredAt: draft.date,
                                    note: draft.note,
                                    sourceRawValue: draft.source.rawValue,
                                    scheduledRuleID: metadata.ruleID,
                                    scheduledYear: metadata.month.year,
                                    scheduledMonth: metadata.month.month,
                                    scheduledOccurrenceKey: metadata.occurrenceKey,
                                    createdAt: now,
                                    updatedAt: now
                                )
                                modelContext.insert(entryRecord)
                                modelContext.insert(LedgerSchemaV3.ScheduledOccurrenceRecord(
                                    id: LedgerScheduledStorageIdentity.occurrenceID(
                                        occurrenceKey: metadata.occurrenceKey
                                    ),
                                    occurrenceKey: metadata.occurrenceKey,
                                    ruleID: metadata.ruleID,
                                    year: metadata.month.year,
                                    month: metadata.month.month,
                                    entryID: entryID,
                                    scheduledDate: scheduledDate,
                                    handledAt: now
                                ))
                                handledKeys.insert(metadata.occurrenceKey)
                                generatedEntries.append(LedgerEntry(
                                    id: entryID,
                                    draft: draft,
                                    createdAt: now,
                                    updatedAt: now
                                ))
                            }
                        }
                    }
                    if month == currentMonth { break }
                    month = try month.next()
                }
            }
            if modelContext.hasChanges { try modelContext.save() }
            generatedEntries.sort {
                $0.date == $1.date
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.date < $1.date
            }
            return LedgerScheduledProcessingResult(
                generatedEntries: generatedEntries,
                skippedOccurrenceCount: skippedOccurrenceCount
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func nextScheduledEntryDate(
        after now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> Date? {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw LedgerScheduledEntryError.invalidDate
        }
        let currentMonth = try LedgerYearMonth.containing(
            now,
            calendar: calendar,
            timeZone: timeZone
        )
        let groups = Dictionary(
            grouping: try activeScheduledRuleVersionRecords(),
            by: \.ruleID
        )
        var earliestDate: Date?
        for records in groups.values {
            let ordered = records.sorted(by: Self.isEarlierVersion)
            guard let candidate = try Self.nextDate(
                in: ordered,
                after: now,
                currentMonth: currentMonth,
                calendar: calendar,
                timeZone: timeZone
            ) else { continue }
            earliestDate = earliestDate.map { min($0, candidate) } ?? candidate
        }
        return earliestDate
    }

    private func saveToggledRuleVersion(
        id: UUID,
        effectiveMonth: LedgerYearMonth,
        isEnabled: Bool,
        updatedAt: Date
    ) throws -> LedgerScheduledEntryRule {
        do {
            let allRecords = try modelContext.fetch(
                FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>()
            )
            let active = allRecords.filter { $0.ruleID == id && $0.deletedAt == nil }
            guard let base = try Self.applicableVersion(in: active, for: effectiveMonth) else {
                throw LedgerScheduledEntryRepositoryError.ruleNotFound(id)
            }
            let baseRule = try Self.scheduledRule(base)
            let version = try LedgerScheduledEntryRule(
                id: id,
                bookID: baseRule.bookID,
                categoryID: baseRule.categoryID,
                kind: baseRule.kind,
                amount: baseRule.amount,
                note: baseRule.note,
                monthlyDay: baseRule.monthlyDay,
                isEnabled: isEnabled,
                effectiveStartMonth: effectiveMonth,
                createdAt: baseRule.createdAt,
                updatedAt: updatedAt
            )
            try validateRuleReferences(version)
            try replaceOrInsertRuleVersion(version, records: allRecords)
            try modelContext.save()
            return version
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func activeScheduledRuleVersionRecords() throws
        -> [LedgerSchemaV3.ScheduledRuleVersionRecord] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>())
            .filter { $0.deletedAt == nil }
    }

    private func validateRuleReferences(_ rule: LedgerScheduledEntryRule) throws {
        let books = try activeScheduleBooks()
        let categories = try activeScheduleCategories()
        guard books.contains(where: { $0.id == rule.bookID }) else {
            throw LedgerError.bookNotFound(rule.bookID)
        }
        guard let category = categories.first(where: { $0.id == rule.categoryID }) else {
            throw LedgerError.categoryNotFound(rule.categoryID)
        }
        guard category.kind == rule.kind else { throw LedgerError.categoryKindMismatch }
    }

    private func activeScheduleBooks() throws -> [LedgerBook] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>())
            .filter { $0.deletedAt == nil }
            .map { LedgerBook(id: $0.id, name: $0.name) }
    }

    private func activeScheduleCategories() throws -> [LedgerCategory] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.CategoryRecord>())
            .filter { $0.deletedAt == nil }
            .map { record in
                guard let kind = LedgerEntryKind(rawValue: record.kindRawValue) else {
                    throw LedgerStorageError.invalidStoredValue(entity: "分类", field: "收支类型")
                }
                return LedgerCategory(id: record.id, name: record.name, kind: kind)
            }
    }

    private func replaceOrInsertRuleVersion(
        _ rule: LedgerScheduledEntryRule,
        records: [LedgerSchemaV3.ScheduledRuleVersionRecord]
    ) throws {
        let sameMonthRecords = records.filter {
            $0.ruleID == rule.id
                && $0.effectiveYear == rule.effectiveStartMonth.year
                && $0.effectiveMonth == rule.effectiveStartMonth.month
        }
        let activeRecords = sameMonthRecords.filter { $0.deletedAt == nil }
        if let record = activeRecords.max(by: Self.isEarlierUpdate) {
            Self.apply(rule, to: record)
            for duplicate in activeRecords where duplicate.persistentModelID != record.persistentModelID {
                modelContext.delete(duplicate)
            }
            return
        }
        if !sameMonthRecords.isEmpty {
            throw LedgerScheduledEntryRepositoryError.ruleNotFound(rule.id)
        }
        modelContext.insert(Self.ruleRecord(rule))
    }

    private static func ruleRecord(
        _ rule: LedgerScheduledEntryRule
    ) -> LedgerSchemaV3.ScheduledRuleVersionRecord {
        let dayValues: (rawValue: String, fixedDay: Int?) = switch rule.monthlyDay {
        case let .fixed(day): ("fixed", day)
        case .lastDay: ("lastDay", nil)
        }
        return LedgerSchemaV3.ScheduledRuleVersionRecord(
            versionID: LedgerScheduledStorageIdentity.versionID(
                ruleID: rule.id,
                month: rule.effectiveStartMonth
            ),
            ruleID: rule.id,
            effectiveYear: rule.effectiveStartMonth.year,
            effectiveMonth: rule.effectiveStartMonth.month,
            bookID: rule.bookID,
            categoryID: rule.categoryID,
            kindRawValue: rule.kind.rawValue,
            amountMinorUnits: rule.amount.minorUnits,
            note: rule.note,
            monthlyDayRawValue: dayValues.rawValue,
            fixedDay: dayValues.fixedDay,
            isEnabled: rule.isEnabled,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt
        )
    }

    private static func apply(
        _ rule: LedgerScheduledEntryRule,
        to record: LedgerSchemaV3.ScheduledRuleVersionRecord
    ) {
        let dayValues: (rawValue: String, fixedDay: Int?) = switch rule.monthlyDay {
        case let .fixed(day): ("fixed", day)
        case .lastDay: ("lastDay", nil)
        }
        record.bookID = rule.bookID
        record.categoryID = rule.categoryID
        record.kindRawValue = rule.kind.rawValue
        record.amountMinorUnits = rule.amount.minorUnits
        record.note = rule.note
        record.monthlyDayRawValue = dayValues.rawValue
        record.fixedDay = dayValues.fixedDay
        record.isEnabled = rule.isEnabled
        record.createdAt = rule.createdAt
        record.updatedAt = rule.updatedAt
    }

    private static func scheduledRule(
        _ record: LedgerSchemaV3.ScheduledRuleVersionRecord
    ) throws -> LedgerScheduledEntryRule {
        guard let kind = LedgerEntryKind(rawValue: record.kindRawValue) else {
            throw LedgerStorageError.invalidStoredValue(entity: "定时规则", field: "收支类型")
        }
        let monthlyDay: LedgerMonthlyDay
        switch record.monthlyDayRawValue {
        case "fixed":
            guard let day = record.fixedDay else {
                throw LedgerStorageError.invalidStoredValue(entity: "定时规则", field: "每月日期")
            }
            monthlyDay = .fixed(day)
        case "lastDay":
            guard record.fixedDay == nil else {
                throw LedgerStorageError.invalidStoredValue(entity: "定时规则", field: "每月日期")
            }
            monthlyDay = .lastDay
        default:
            throw LedgerStorageError.invalidStoredValue(entity: "定时规则", field: "每月日期")
        }
        return try LedgerScheduledEntryRule(
            id: record.ruleID,
            bookID: record.bookID,
            categoryID: record.categoryID,
            kind: kind,
            amount: LedgerAmount(minorUnits: record.amountMinorUnits),
            note: record.note,
            monthlyDay: monthlyDay,
            isEnabled: record.isEnabled,
            effectiveStartMonth: effectiveMonth(record),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private static func effectiveMonth(
        _ record: LedgerSchemaV3.ScheduledRuleVersionRecord
    ) throws -> LedgerYearMonth {
        try LedgerYearMonth(year: record.effectiveYear, month: record.effectiveMonth)
    }

    private static func isEarlierVersion(
        _ left: LedgerSchemaV3.ScheduledRuleVersionRecord,
        _ right: LedgerSchemaV3.ScheduledRuleVersionRecord
    ) -> Bool {
        (left.effectiveYear, left.effectiveMonth, left.versionID.uuidString)
            < (right.effectiveYear, right.effectiveMonth, right.versionID.uuidString)
    }

    private static func isEarlierUpdate(
        _ left: LedgerSchemaV3.ScheduledRuleVersionRecord,
        _ right: LedgerSchemaV3.ScheduledRuleVersionRecord
    ) -> Bool {
        (left.updatedAt, left.versionID.uuidString)
            < (right.updatedAt, right.versionID.uuidString)
    }

    private static func applicableVersion(
        in records: [LedgerSchemaV3.ScheduledRuleVersionRecord],
        for month: LedgerYearMonth
    ) throws -> LedgerSchemaV3.ScheduledRuleVersionRecord? {
        try records
            .filter { try effectiveMonth($0) <= month }
            .max(by: isEarlierVersion)
    }

    private static func nextDate(
        in records: [LedgerSchemaV3.ScheduledRuleVersionRecord],
        after now: Date,
        currentMonth: LedgerYearMonth,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> Date? {
        guard let first = records.first else { return nil }
        var month = max(currentMonth, try effectiveMonth(first))
        while true {
            guard let selected = try applicableVersion(in: records, for: month) else {
                month = try month.next()
                continue
            }
            if selected.isEnabled {
                let rule = try scheduledRule(selected)
                let date = try LedgerScheduledEntryPlanner.scheduledDate(
                    for: rule.monthlyDay,
                    in: month,
                    calendar: calendar,
                    timeZone: timeZone
                )
                if date > now { return date }
                month = try month.next()
                continue
            }
            let laterMonths = try records
                .map(effectiveMonth)
                .filter { $0 > month }
            guard let nextEnabledBoundary = laterMonths.min() else { return nil }
            month = nextEnabledBoundary
        }
    }
}

enum LedgerScheduledStorageIdentity {
    static func versionID(ruleID: UUID, month: LedgerYearMonth) -> UUID {
        make(namespace: "scheduled-rule-version-v1", value: "\(ruleID.uuidString.lowercased()):\(month.key)")
    }

    static func occurrenceID(occurrenceKey: String) -> UUID {
        make(namespace: "scheduled-occurrence-v1", value: occurrenceKey)
    }

    static func entryID(occurrenceKey: String) -> UUID {
        make(namespace: "scheduled-entry-v1", value: occurrenceKey)
    }

    private static func make(namespace: String, value: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace)\u{0}\(value)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
