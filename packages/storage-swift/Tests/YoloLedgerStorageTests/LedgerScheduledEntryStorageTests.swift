import Foundation
import SwiftData
import Testing
import YoloLedgerCore
@testable import YoloLedgerStorage

struct LedgerScheduledEntryStorageTests {
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    @Test @MainActor func sameMonthEditsPauseAndResumeReplaceOnePersistedVersion() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let id = UUID()
        let january = try scheduledRule(
            id: id,
            amount: 100,
            day: .fixed(15),
            month: LedgerYearMonth(year: 2026, month: 1)
        )
        let januaryEdit = try scheduledRule(
            id: id,
            amount: 150,
            day: .fixed(20),
            month: LedgerYearMonth(year: 2026, month: 1),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let march = try scheduledRule(
            id: id,
            amount: 200,
            day: .fixed(8),
            month: LedgerYearMonth(year: 2026, month: 3),
            updatedAt: Date(timeIntervalSince1970: 1_740_000_000)
        )

        #expect(try await repository.saveScheduledEntryRuleVersion(january) == january)
        #expect(try await repository.saveScheduledEntryRuleVersion(januaryEdit) == januaryEdit)
        #expect(try await repository.fetchScheduledEntryRules() == [januaryEdit])
        let paused = try await repository.pauseScheduledEntryRule(
            id: id,
            effectiveMonth: january.effectiveStartMonth,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        #expect(!paused.isEnabled)
        let resumed = try await repository.resumeScheduledEntryRule(
            id: id,
            effectiveStartMonth: january.effectiveStartMonth,
            updatedAt: Date(timeIntervalSince1970: 1_730_000_000)
        )
        #expect(resumed.isEnabled)
        #expect(resumed.amount.minorUnits == januaryEdit.amount.minorUnits)
        #expect(resumed.monthlyDay == januaryEdit.monthlyDay)

        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let records = try ModelContext(container).fetch(
                FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>()
            )
            #expect(records.count == 1)
            #expect(records.first?.isEnabled == true)
            #expect(records.first?.amountMinorUnits == 150)
            #expect(records.first?.fixedDay == 20)
        }

        #expect(try await repository.saveScheduledEntryRuleVersion(march) == march)
        #expect(try await repository.fetchScheduledEntryRules() == [march])

        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let records = try ModelContext(container).fetch(
                FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>()
            )
            #expect(records.count == 2)
        }

        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchScheduledEntryRules() == [march])
    }

    @Test func processingUsesTheVersionEffectiveForEachMonthAndClampsMonthEnd() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let id = UUID()
        _ = try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
            id: id,
            amount: 100,
            day: .fixed(31),
            month: LedgerYearMonth(year: 2026, month: 1)
        ))
        _ = try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
            id: id,
            amount: 200,
            day: .fixed(5),
            month: LedgerYearMonth(year: 2026, month: 3),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        ))
        let now = localDate(2026, 4, 10, hour: 12)

        let first = try await repository.processDueScheduledEntries(
            now: now,
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(first.generatedCount == 4)
        #expect(first.skippedOccurrenceCount == 0)
        #expect(first.generatedEntries.compactMap { $0.scheduledOccurrence?.month.key }
            == ["2026-01", "2026-02", "2026-03", "2026-04"])
        #expect(first.generatedEntries.map(\.amount.minorUnits) == [100, 100, 200, 200])
        #expect(first.generatedEntries.map { calendar().component(.day, from: $0.date) }
            == [31, 28, 5, 5])
        #expect(first.generatedEntries.allSatisfy {
            $0.source == .scheduled && $0.importMetadata == nil
        })

        _ = try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
            id: id,
            amount: 999,
            day: .fixed(1),
            month: LedgerYearMonth(year: 2026, month: 1),
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000)
        ))

        let repeated = try await repository.processDueScheduledEntries(
            now: now,
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(repeated.generatedCount == 0)
        #expect(repeated.skippedOccurrenceCount == 4)
        let unchangedEntries = try await repository.fetchEntries()
        #expect(unchangedEntries.count == 4)
        #expect(unchangedEntries.map(\.amount.minorUnits).sorted() == [100, 100, 200, 200])

        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let afterReopen = try await reopened.processDueScheduledEntries(
            now: now,
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(afterReopen.generatedCount == 0)
        #expect(afterReopen.skippedOccurrenceCount == 4)
    }

    @Test func pauseResumeAndFutureVersionsControlProcessingAndNextDate() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let id = UUID()
        let january = try LedgerYearMonth(year: 2026, month: 1)
        let march = try LedgerYearMonth(year: 2026, month: 3)
        let may = try LedgerYearMonth(year: 2026, month: 5)
        _ = try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
            id: id,
            amount: 1_000,
            day: .fixed(10),
            month: january
        ))
        let paused = try await repository.pauseScheduledEntryRule(
            id: id,
            effectiveMonth: march,
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        #expect(!paused.isEnabled)
        let resumed = try await repository.resumeScheduledEntryRule(
            id: id,
            effectiveStartMonth: may,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        #expect(resumed.isEnabled)
        #expect(try await repository.fetchScheduledEntryRules() == [resumed])

        let next = try await repository.nextScheduledEntryDate(
            after: localDate(2026, 2, 15, hour: 12),
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(next == localDate(2026, 5, 10, hour: 0))

        let result = try await repository.processDueScheduledEntries(
            now: localDate(2026, 6, 20, hour: 12),
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(result.generatedEntries.compactMap { $0.scheduledOccurrence?.month.key }
            == ["2026-01", "2026-02", "2026-05", "2026-06"])
    }

    @Test @MainActor func deletingGeneratedEntryKeepsOccurrenceAndDeletingRuleStopsFutureWork() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let id = UUID()
        _ = try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
            id: id,
            amount: 500,
            day: .lastDay,
            month: LedgerYearMonth(year: 2026, month: 1)
        ))
        let januaryNow = localDate(2026, 1, 31, hour: 12)
        let generated = try await repository.processDueScheduledEntries(
            now: januaryNow,
            calendar: calendar(),
            timeZone: timeZone
        )
        let entry = try #require(generated.generatedEntries.first)
        try await repository.deleteEntry(id: entry.id)

        let afterEntryDeletion = try await repository.processDueScheduledEntries(
            now: januaryNow,
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(afterEntryDeletion.generatedCount == 0)
        #expect(afterEntryDeletion.skippedOccurrenceCount == 1)
        #expect(try await repository.fetchEntries().isEmpty)

        let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<LedgerSchemaV3.ScheduledOccurrenceRecord>()).count == 1)
        let storedEntry = try #require(context.fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())
            .first { $0.id == entry.id })
        #expect(storedEntry.deletedAt != nil)
        #expect(storedEntry.scheduledOccurrenceKey == entry.scheduledOccurrence?.occurrenceKey)

        try await repository.deleteScheduledEntryRule(
            id: id,
            deletedAt: localDate(2026, 2, 1, hour: 0)
        )
        #expect(try await repository.fetchScheduledEntryRules().isEmpty)
        await #expect(throws: LedgerScheduledEntryRepositoryError.ruleNotFound(id)) {
            try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
                id: id,
                amount: 600,
                day: .fixed(15),
                month: LedgerYearMonth(year: 2026, month: 1),
                updatedAt: Date(timeIntervalSince1970: 1_730_000_000)
            ))
        }
        let afterRuleDeletion = try await repository.processDueScheduledEntries(
            now: localDate(2026, 6, 30, hour: 12),
            calendar: calendar(),
            timeZone: timeZone
        )
        #expect(afterRuleDeletion.generatedCount == 0)
        #expect(try context.fetch(FetchDescriptor<LedgerSchemaV3.ScheduledOccurrenceRecord>()).count == 1)
    }

    @Test func concurrentProcessingCreatesEachOccurrenceOnlyOnce() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        _ = try await repository.saveScheduledEntryRuleVersion(try scheduledRule(
            id: UUID(),
            amount: 888,
            day: .fixed(8),
            month: LedgerYearMonth(year: 2026, month: 11)
        ))
        let now = localDate(2026, 11, 8, hour: 12)
        async let first = repository.processDueScheduledEntries(
            now: now,
            calendar: calendar(),
            timeZone: timeZone
        )
        async let second = repository.processDueScheduledEntries(
            now: now,
            calendar: calendar(),
            timeZone: timeZone
        )
        let results = try await [first, second]
        #expect(results.map(\.generatedCount).sorted() == [0, 1])
        #expect(try await repository.fetchEntries().count == 1)
    }

    @Test @MainActor func folderSyncCarriesGeneratedEntryMetadataButKeepsSchedulingStateLocal() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(
            at: directory.exchangeURL,
            withIntermediateDirectories: true
        )
        let source = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let destination = try SwiftDataLedgerRepository(storeURL: directory.secondStoreURL)
        let ruleID = UUID()
        _ = try await source.saveScheduledEntryRuleVersion(try scheduledRule(
            id: ruleID,
            amount: 660,
            day: .fixed(6),
            month: LedgerYearMonth(year: 2026, month: 11)
        ))
        let processed = try await source.processDueScheduledEntries(
            now: localDate(2026, 11, 6, hour: 12),
            calendar: calendar(),
            timeZone: timeZone
        )
        let generated = try #require(processed.generatedEntries.first)

        _ = try await source.synchronize(folderURL: directory.exchangeURL, deviceID: UUID())
        _ = try await destination.synchronize(folderURL: directory.exchangeURL, deviceID: UUID())

        let imported = try #require(try await destination.fetchEntries().first)
        #expect(imported.id == generated.id)
        #expect(imported.source == .scheduled)
        #expect(imported.scheduledOccurrence == generated.scheduledOccurrence)
        #expect(try await destination.fetchScheduledEntryRules().isEmpty)

        let container = try LocalLedgerStore.makeContainer(at: directory.secondStoreURL)
        let context = ModelContext(container)
        #expect(try context.fetch(
            FetchDescriptor<LedgerSchemaV3.ScheduledRuleVersionRecord>()
        ).isEmpty)
        #expect(try context.fetch(
            FetchDescriptor<LedgerSchemaV3.ScheduledOccurrenceRecord>()
        ).isEmpty)
    }

    @Test @MainActor func versionTwoStoreMigratesToV3WithEveryExistingFieldIntact() async throws {
        let directory = ScheduledTestDirectory()
        defer { directory.remove() }
        let entryID = UUID()
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_123)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_456)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_789)
        let metadata = LedgerEntryImportMetadata(
            format: .meowLedgerCSVV1,
            deduplicationKey: "meow-ledger-csv-v1:test-v2",
            originalCategory: "原分类",
            originalTimestamp: "2026-01-02 03:04:05",
            originalAmount: "-12.34",
            originalAccount: "原账户",
            originalBook: "原账本",
            originalCurrency: "CNY",
            originalNote: "原备注"
        )
        do {
            let schema = Schema(versionedSchema: LedgerSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    "LegacyV2",
                    schema: schema,
                    url: directory.storeURL,
                    cloudKitDatabase: .none
                )]
            )
            let context = ModelContext(container)
            let book = LedgerSeedData.defaultBook
            let category = LedgerSeedData.categories[0]
            context.insert(LedgerSchemaV2.BookRecord(
                id: book.id,
                name: book.name,
                sortOrder: 0,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
            context.insert(LedgerSchemaV2.CategoryRecord(
                id: category.id,
                name: category.name,
                kindRawValue: category.kind.rawValue,
                sortOrder: 0,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
            context.insert(LedgerSchemaV2.EntryRecord(
                id: entryID,
                bookID: book.id,
                categoryID: category.id,
                kindRawValue: category.kind.rawValue,
                amountMinorUnits: 1_234,
                occurredAt: occurredAt,
                note: "V2 保留",
                sourceRawValue: LedgerEntrySource.meowLedgerImport.rawValue,
                importFormatRawValue: metadata.format.rawValue,
                importDeduplicationKey: metadata.deduplicationKey,
                importOriginalCategory: metadata.originalCategory,
                importOriginalTimestamp: metadata.originalTimestamp,
                importOriginalAmount: metadata.originalAmount,
                importOriginalAccount: metadata.originalAccount,
                importOriginalBook: metadata.originalBook,
                importOriginalCurrency: metadata.originalCurrency,
                importOriginalNote: metadata.originalNote,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
            context.insert(LedgerSchemaV2.StoreMetadata(key: "starter-choices-v1"))
            context.insert(LedgerSchemaV2.StoreMetadata(key: "starter-categories-v2"))
            try context.save()
        }
        try Data("2.0.0\n".utf8).write(
            to: StoreUpgradeSnapshot.schemaMarkerURL(for: directory.storeURL),
            options: .atomic
        )

        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let entry = try #require(try await repository.fetchEntries().first { $0.id == entryID })
        #expect(entry.amount.minorUnits == 1_234)
        #expect(entry.date == occurredAt)
        #expect(entry.createdAt == createdAt)
        #expect(entry.updatedAt == updatedAt)
        #expect(entry.note == "V2 保留")
        #expect(entry.importMetadata == metadata)
        #expect(entry.scheduledOccurrence == nil)
        #expect(FileManager.default.fileExists(atPath: StoreUpgradeSnapshot.snapshotStoreURL(
            for: directory.storeURL,
            targetSchemaVersion: "3.0.0"
        ).path))
    }

    private func scheduledRule(
        id: UUID,
        amount: Int64,
        day: LedgerMonthlyDay,
        month: LedgerYearMonth,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> LedgerScheduledEntryRule {
        try LedgerScheduledEntryRule(
            id: id,
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: LedgerSeedData.categories[0].id,
            kind: .expense,
            amount: LedgerAmount(minorUnits: amount),
            note: "固定记账",
            monthlyDay: day,
            isEnabled: true,
            effectiveStartMonth: month,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: updatedAt
        )
    }

    private func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    private func localDate(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        calendar().date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}

private struct ScheduledTestDirectory {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("YoloLedgerScheduledStorageTests-\(UUID())", isDirectory: true)
    var storeURL: URL { url.appendingPathComponent("ledger.store") }
    var secondStoreURL: URL { url.appendingPathComponent("second/ledger.store") }
    var exchangeURL: URL { url.appendingPathComponent("exchange", isDirectory: true) }
    func remove() { try? FileManager.default.removeItem(at: url) }
}
