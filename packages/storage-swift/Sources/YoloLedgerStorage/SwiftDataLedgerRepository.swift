import Foundation
import SwiftData
import YoloLedgerCore

/// A local, disk-backed repository. Create one instance per active app store.
public struct SwiftDataLedgerRepository: LedgerRepository, LedgerFolderSyncing, LedgerScheduledEntryRepository {
    public let storeURL: URL
    private let store: LedgerStoreActor
    private let syncMonitor: CloudSyncMonitor

    /// Opens the database, initializes starter choices and applies pending seed-data revisions.
    /// Failures propagate to the caller; no in-memory or destructive fallback is used.
    public init(storeURL: URL, syncMode: LedgerSyncMode = .local) throws {
        self.storeURL = storeURL
        self.store = try LedgerStoreActor(storeURL: storeURL, syncMode: syncMode)
        self.syncMonitor = CloudSyncMonitor(syncMode: syncMode)
    }

    /// Resolves Application Support/YoloLedger/ledger.store inside the app's container.
    public static func defaultStoreURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(YoloLedgerProduct.applicationSupportDirectoryName, isDirectory: true)
        .appendingPathComponent("ledger.store", isDirectory: false)
    }

    public func fetchBooks() async throws -> [LedgerBook] {
        try await store.fetchBooks()
    }

    public func fetchCategories() async throws -> [LedgerCategory] {
        try await store.fetchCategories()
    }

    public func fetchEntries(bookID: UUID?) async throws -> [LedgerEntry] {
        try await store.fetchEntries(bookID: bookID)
    }

    public func fetchEntries(bookID: UUID, dateRange: LedgerDateRange) async throws -> [LedgerEntry] {
        try await store.fetchEntries(bookID: bookID, dateRange: dateRange)
    }

    public func fetchRecentNotes(categoryID: UUID, limit: Int) async throws -> [String] {
        try await store.fetchRecentNotes(categoryID: categoryID, limit: limit)
    }

    public func createEntry(_ draft: LedgerEntryDraft, id: UUID) async throws -> LedgerEntry {
        try await store.createEntry(draft, id: id)
    }

    public func updateEntry(id: UUID, draft: LedgerEntryDraft) async throws -> LedgerEntry {
        try await store.updateEntry(id: id, draft: draft)
    }

    public func deleteEntry(id: UUID) async throws {
        try await store.deleteEntry(id: id)
    }

    public func createBook(name: String, id: UUID) async throws -> LedgerBook {
        try await store.createBook(name: name, id: id)
    }

    public func renameBook(id: UUID, name: String) async throws -> LedgerBook {
        try await store.renameBook(id: id, name: name)
    }

    public func updates() -> AsyncStream<Void> { syncMonitor.updates() }

    public func currentSyncState() -> LedgerSyncState { syncMonitor.currentState() }

    public func synchronize(folderURL: URL, deviceID: UUID) async throws -> LedgerFolderSyncReport {
        // Decode and validate every visible device snapshot before opening a local merge transaction.
        let snapshots = try LedgerFolderSnapshotIO.readAll(from: folderURL)
        let generatedAt = Date()
        let mergeResult = try await store.mergeFolderSnapshots(
            snapshots,
            deviceID: deviceID,
            generatedAt: generatedAt
        )
        try LedgerFolderSnapshotIO.write(mergeResult.snapshot, to: folderURL)
        let completedAt = Date()
        let report = LedgerFolderSyncReport(
            importedRecordCount: mergeResult.importedRecordCount,
            exportedRecordCount: mergeResult.snapshot.books.count
                + mergeResult.snapshot.categories.count
                + mergeResult.snapshot.entries.count,
            completedAt: completedAt
        )
        syncMonitor.notifyExternalChange()
        return report
    }

    public func importMeowLedger(
        plans: [LedgerMeowImportPlan]
    ) async throws -> LedgerMeowImportBatchReport {
        let report = try await store.importMeowLedger(
            plans: plans,
            batchID: UUID(),
            startedAt: Date()
        )
        syncMonitor.notifyExternalChange()
        return report
    }

    public func makeMeowImportHandler() -> LedgerMeowImportHandler {
        let repository = self
        return { plans in
            try await repository.importMeowLedger(plans: plans)
        }
    }

    public func fetchScheduledEntryRules() async throws -> [LedgerScheduledEntryRule] {
        try await store.fetchScheduledEntryRules()
    }

    @discardableResult
    public func saveScheduledEntryRuleVersion(
        _ rule: LedgerScheduledEntryRule
    ) async throws -> LedgerScheduledEntryRule {
        try await store.saveScheduledEntryRuleVersion(rule)
    }

    @discardableResult
    public func pauseScheduledEntryRule(
        id: UUID,
        effectiveMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule {
        try await store.pauseScheduledEntryRule(
            id: id,
            effectiveMonth: effectiveMonth,
            updatedAt: updatedAt
        )
    }

    @discardableResult
    public func resumeScheduledEntryRule(
        id: UUID,
        effectiveStartMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule {
        try await store.resumeScheduledEntryRule(
            id: id,
            effectiveStartMonth: effectiveStartMonth,
            updatedAt: updatedAt
        )
    }

    public func deleteScheduledEntryRule(id: UUID, deletedAt: Date) async throws {
        try await store.deleteScheduledEntryRule(id: id, deletedAt: deletedAt)
    }

    public func processDueScheduledEntries(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> LedgerScheduledProcessingResult {
        try await store.processDueScheduledEntries(
            now: now,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    public func nextScheduledEntryDate(
        after now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> Date? {
        try await store.nextScheduledEntryDate(
            after: now,
            calendar: calendar,
            timeZone: timeZone
        )
    }
}

actor LedgerStoreActor: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    nonisolated let storeURL: URL

    init(storeURL: URL, syncMode: LedgerSyncMode) throws {
        let container = try LocalLedgerStore.makeContainer(at: storeURL, syncMode: syncMode)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try Self.reconcileBootstrapRecords(in: context)
        try LedgerSeedBootstrap.initialize(in: context)
        self.storeURL = storeURL
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    func fetchBooks() throws -> [LedgerBook] {
        return try activeBooks()
    }

    private func activeBooks() throws -> [LedgerBook] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
            .sorted { left, right in
                left.sortOrder == right.sortOrder
                    ? left.id.uuidString < right.id.uuidString
                    : left.sortOrder < right.sortOrder
            }
            .map { LedgerBook(id: $0.id, name: $0.name) }
    }

    func fetchCategories() throws -> [LedgerCategory] {
        return try activeCategories()
    }

    private func activeCategories() throws -> [LedgerCategory] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.CategoryRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
            .sorted { left, right in
                left.sortOrder == right.sortOrder
                    ? left.id.uuidString < right.id.uuidString
                    : left.sortOrder < right.sortOrder
            }
            .map { record in
                guard let kind = LedgerEntryKind(rawValue: record.kindRawValue) else {
                    throw LedgerStorageError.invalidStoredValue(entity: "分类", field: "收支类型")
                }
                return LedgerCategory(id: record.id, name: record.name, kind: kind)
            }
    }

    func fetchEntries(bookID: UUID?) throws -> [LedgerEntry] {
        // Keep the legacy unbounded API self-healing for sync/import maintenance callers.
        // Launch uses the bounded overload below and never pays for this full-table pass.
        try reconcileDuplicates()
        let books = try activeBooks()
        let categories = try activeCategories()
        var descriptor = FetchDescriptor<LedgerSchemaV3.EntryRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        if let selectedID = bookID {
            guard books.contains(where: { $0.id == selectedID }) else {
                throw LedgerError.bookNotFound(selectedID)
            }
            descriptor.predicate = #Predicate { $0.bookID == selectedID && $0.deletedAt == nil }
        }
        return try modelContext.fetch(descriptor)
            .map { record in
                let entry = try Self.entry(from: record)
                try LedgerValidation.validate(entry.draft, books: books, categories: categories)
                return entry
            }
            .sorted { left, right in
                if left.date != right.date { return left.date > right.date }
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
    }

    func fetchEntries(bookID: UUID, dateRange: LedgerDateRange) throws -> [LedgerEntry] {
        let books = try activeBooks()
        guard books.contains(where: { $0.id == bookID }) else {
            throw LedgerError.bookNotFound(bookID)
        }
        let categories = try activeCategories()
        let rangeStart = dateRange.start
        let rangeEnd = dateRange.end
        let descriptor = FetchDescriptor<LedgerSchemaV3.EntryRecord>(
            predicate: #Predicate {
                $0.bookID == bookID
                    && $0.occurredAt >= rangeStart
                    && $0.occurredAt < rangeEnd
                    && $0.deletedAt == nil
            },
            sortBy: [
                SortDescriptor(\.occurredAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        )
        return try modelContext.fetch(descriptor)
            .map { record in
                let entry = try Self.entry(from: record)
                try LedgerValidation.validate(entry.draft, books: books, categories: categories)
                return entry
            }
            .sorted { left, right in
                if left.date != right.date { return left.date > right.date }
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
    }

    func fetchRecentNotes(categoryID: UUID, limit: Int) throws -> [String] {
        guard limit > 0 else { return [] }
        let descriptor = FetchDescriptor<LedgerSchemaV3.EntryRecord>(
            predicate: #Predicate { $0.categoryID == categoryID && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.updatedAt),
                SortDescriptor(\.createdAt),
                SortDescriptor(\.occurredAt),
            ]
        )
        var seen = Set<String>()
        var notes: [String] = []
        for record in try modelContext.fetch(descriptor) {
            let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            let key = note.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { continue }
            notes.append(note)
        }
        return Array(notes.suffix(limit))
    }

    func createEntry(_ draft: LedgerEntryDraft, id: UUID) throws -> LedgerEntry {
        guard try findEntry(id: id, includesDeleted: true) == nil else {
            throw LedgerError.duplicateIdentifier(id)
        }
        try validate(draft)
        try Self.validateImportMetadata(draft)
        try Self.validateScheduledMetadata(draft)
        let now = Date()
        let importMetadata = draft.importMetadata
        let scheduledOccurrence = draft.scheduledOccurrence
        let record = LedgerSchemaV3.EntryRecord(
            id: id,
            bookID: draft.bookID,
            categoryID: draft.categoryID,
            kindRawValue: draft.kind.rawValue,
            amountMinorUnits: draft.amount.minorUnits,
            occurredAt: draft.date,
            note: draft.note,
            sourceRawValue: draft.source.rawValue,
            importFormatRawValue: importMetadata?.format.rawValue,
            importDeduplicationKey: importMetadata?.deduplicationKey,
            importOriginalCategory: importMetadata?.originalCategory,
            importOriginalTimestamp: importMetadata?.originalTimestamp,
            importOriginalAmount: importMetadata?.originalAmount,
            importOriginalAccount: importMetadata?.originalAccount,
            importOriginalBook: importMetadata?.originalBook,
            importOriginalCurrency: importMetadata?.originalCurrency,
            importOriginalNote: importMetadata?.originalNote,
            scheduledRuleID: scheduledOccurrence?.ruleID,
            scheduledYear: scheduledOccurrence?.month.year,
            scheduledMonth: scheduledOccurrence?.month.month,
            scheduledOccurrenceKey: scheduledOccurrence?.occurrenceKey,
            createdAt: now,
            updatedAt: now
        )
        return try save {
            modelContext.insert(record)
            return try Self.entry(from: record)
        }
    }

    func updateEntry(id: UUID, draft: LedgerEntryDraft) throws -> LedgerEntry {
        guard let record = try findEntry(id: id) else { throw LedgerError.entryNotFound(id) }
        try validate(draft)
        return try save {
            record.bookID = draft.bookID
            record.categoryID = draft.categoryID
            record.kindRawValue = draft.kind.rawValue
            record.amountMinorUnits = draft.amount.minorUnits
            record.occurredAt = draft.date
            record.note = draft.note
            record.updatedAt = max(Date(), record.updatedAt)
            return try Self.entry(from: record)
        }
    }

    func deleteEntry(id: UUID) throws {
        guard let record = try findEntry(id: id) else { throw LedgerError.entryNotFound(id) }
        try save {
            let now = Date()
            record.deletedAt = now
            record.updatedAt = max(now, record.updatedAt)
        }
    }

    func createBook(name: String, id: UUID) throws -> LedgerBook {
        let normalizedName = try LedgerValidation.normalizedName(name)
        guard try findBook(id: id, includesDeleted: true) == nil else {
            throw LedgerError.duplicateIdentifier(id)
        }
        let records = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        let (order, overflow) = (records.map(\.sortOrder).max() ?? -1).addingReportingOverflow(1)
        guard !overflow else {
            throw LedgerStorageError.invalidStoredValue(entity: "账本", field: "排序")
        }
        let record = LedgerSchemaV3.BookRecord(id: id, name: normalizedName, sortOrder: order)
        return try save {
            modelContext.insert(record)
            return LedgerBook(id: record.id, name: record.name)
        }
    }

    func renameBook(id: UUID, name: String) throws -> LedgerBook {
        let normalizedName = try LedgerValidation.normalizedName(name)
        guard let record = try findBook(id: id) else { throw LedgerError.bookNotFound(id) }
        return try save {
            record.name = normalizedName
            record.updatedAt = max(Date(), record.updatedAt)
            return LedgerBook(id: record.id, name: record.name)
        }
    }

    func importMeowLedger(
        plans: [LedgerMeowImportPlan],
        batchID: UUID,
        startedAt: Date
    ) throws -> LedgerMeowImportBatchReport {
        let preparation = try LedgerMeowImportPlanValidator.prepare(plans)
        do {
            let allBooks = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>())
            let allCategories = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.CategoryRecord>())
            let allEntries = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())

            var existingEntriesByDeduplicationKey: [String: [LedgerSchemaV3.EntryRecord]] = [:]
            for entry in allEntries {
                if let key = entry.importDeduplicationKey {
                    existingEntriesByDeduplicationKey[key, default: []].append(entry)
                }
            }

            var pendingRecords: [LedgerMeowImportPreparedRecord] = []
            var skippedDuplicateCount = preparation.duplicateRecordCountWithinBatch
            for prepared in preparation.uniqueRecords {
                let key = prepared.record.importMetadata.deduplicationKey
                if let existing = existingEntriesByDeduplicationKey[key] {
                    guard existing.allSatisfy({ Self.matches($0, importedRecord: prepared.record) }) else {
                        throw LedgerMeowImportStorageError.deduplicationConflict
                    }
                    skippedDuplicateCount += 1
                } else {
                    pendingRecords.append(prepared)
                }
            }

            let activeBooks = allBooks
                .filter { $0.deletedAt == nil }
                .sorted {
                    $0.sortOrder == $1.sortOrder
                        ? $0.id.uuidString < $1.id.uuidString
                        : $0.sortOrder < $1.sortOrder
                }
            var bookIDByName: [String: UUID] = [:]
            for book in activeBooks where bookIDByName[book.name] == nil {
                bookIDByName[book.name] = book.id
            }

            let activeCategories = allCategories
                .filter { $0.deletedAt == nil }
                .sorted {
                    $0.sortOrder == $1.sortOrder
                        ? $0.id.uuidString < $1.id.uuidString
                        : $0.sortOrder < $1.sortOrder
                }
            var categoryIDByKey: [LedgerMeowCategoryMappingKey: UUID] = [:]
            for category in activeCategories {
                guard let kind = LedgerEntryKind(rawValue: category.kindRawValue) else {
                    throw LedgerStorageError.invalidStoredValue(entity: "分类", field: "收支类型")
                }
                let key = LedgerMeowCategoryMappingKey(kind: kind, name: category.name)
                if categoryIDByKey[key] == nil { categoryIDByKey[key] = category.id }
            }

            var plannedBooks: [(id: UUID, name: String, sortOrder: Int)] = []
            var plannedCategories: [(id: UUID, key: LedgerMeowCategoryMappingKey, sortOrder: Int)] = []
            var maximumBookOrder = activeBooks.map(\.sortOrder).max() ?? -1
            var maximumCategoryOrder = activeCategories.map(\.sortOrder).max() ?? -1
            let allBookIDs = Set(allBooks.map(\.id))
            let allCategoryIDs = Set(allCategories.map(\.id))
            let allEntryIDs = Set(allEntries.map(\.id))
            var plannedEntryIDs: Set<UUID> = []

            for prepared in pendingRecords {
                if bookIDByName[prepared.normalizedBookName] == nil {
                    let id = LedgerMeowImportStableID.book(name: prepared.normalizedBookName)
                    guard !allBookIDs.contains(id), !plannedBooks.contains(where: { $0.id == id }) else {
                        throw LedgerMeowImportStorageError.identifierCollision(entity: "账本", id: id)
                    }
                    let order = try Self.nextSortOrder(
                        after: &maximumBookOrder,
                        entity: "账本"
                    )
                    plannedBooks.append((id, prepared.normalizedBookName, order))
                    bookIDByName[prepared.normalizedBookName] = id
                }

                let categoryKey = LedgerMeowCategoryMappingKey(
                    kind: prepared.record.kind,
                    name: prepared.normalizedCategoryName
                )
                if categoryIDByKey[categoryKey] == nil {
                    let id = LedgerMeowImportStableID.category(
                        kind: categoryKey.kind,
                        name: categoryKey.name
                    )
                    guard !allCategoryIDs.contains(id), !plannedCategories.contains(where: { $0.id == id }) else {
                        throw LedgerMeowImportStorageError.identifierCollision(entity: "分类", id: id)
                    }
                    let order = try Self.nextSortOrder(
                        after: &maximumCategoryOrder,
                        entity: "分类"
                    )
                    plannedCategories.append((id, categoryKey, order))
                    categoryIDByKey[categoryKey] = id
                }

                guard !allEntryIDs.contains(prepared.entryID),
                      plannedEntryIDs.insert(prepared.entryID).inserted
                else {
                    throw LedgerMeowImportStorageError.identifierCollision(
                        entity: "账目",
                        id: prepared.entryID
                    )
                }
            }

            let backupURL = try StoreImportSnapshot.create(
                for: storeURL,
                batchID: batchID,
                createdAt: startedAt
            )
            for book in plannedBooks {
                modelContext.insert(LedgerSchemaV3.BookRecord(
                    id: book.id,
                    name: book.name,
                    sortOrder: book.sortOrder,
                    createdAt: startedAt,
                    updatedAt: startedAt
                ))
            }
            for category in plannedCategories {
                modelContext.insert(LedgerSchemaV3.CategoryRecord(
                    id: category.id,
                    name: category.key.name,
                    kindRawValue: category.key.kind.rawValue,
                    sortOrder: category.sortOrder,
                    createdAt: startedAt,
                    updatedAt: startedAt
                ))
            }
            for prepared in pendingRecords {
                let metadata = prepared.record.importMetadata
                let categoryKey = LedgerMeowCategoryMappingKey(
                    kind: prepared.record.kind,
                    name: prepared.normalizedCategoryName
                )
                guard let bookID = bookIDByName[prepared.normalizedBookName],
                      let categoryID = categoryIDByKey[categoryKey]
                else {
                    throw LedgerMeowImportStorageError.inconsistentPlan(
                        planIndex: 0,
                        reason: "账本或分类映射失败"
                    )
                }
                modelContext.insert(LedgerSchemaV3.EntryRecord(
                    id: prepared.entryID,
                    bookID: bookID,
                    categoryID: categoryID,
                    kindRawValue: prepared.record.kind.rawValue,
                    amountMinorUnits: prepared.record.amount.minorUnits,
                    occurredAt: prepared.record.date,
                    note: prepared.record.fields.note,
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
                    createdAt: startedAt,
                    updatedAt: startedAt
                ))
            }
            if modelContext.hasChanges { try modelContext.save() }

            let expenseRecords = pendingRecords.filter { $0.record.kind == .expense }
            let incomeRecords = pendingRecords.filter { $0.record.kind == .income }
            return LedgerMeowImportBatchReport(
                batchID: batchID,
                backupURL: backupURL,
                submittedRecordCount: preparation.submittedRecordCount,
                importedEntryCount: pendingRecords.count,
                skippedDuplicateCount: skippedDuplicateCount,
                createdBookCount: plannedBooks.count,
                createdCategoryCount: plannedCategories.count,
                importedExpenseCount: expenseRecords.count,
                importedIncomeCount: incomeRecords.count,
                importedExpenseTotalMinorUnits: Self.decimalTotal(expenseRecords),
                importedIncomeTotalMinorUnits: Self.decimalTotal(incomeRecords),
                completedAt: Date()
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func matches(
        _ stored: LedgerSchemaV3.EntryRecord,
        importedRecord: LedgerMeowImportRecord
    ) -> Bool {
        let metadata = importedRecord.importMetadata
        return stored.kindRawValue == importedRecord.kind.rawValue
            && stored.amountMinorUnits == importedRecord.amount.minorUnits
            && stored.occurredAt == importedRecord.date
            && stored.note == importedRecord.fields.note
            && stored.sourceRawValue == LedgerEntrySource.meowLedgerImport.rawValue
            && stored.importFormatRawValue == metadata.format.rawValue
            && stored.importDeduplicationKey == metadata.deduplicationKey
            && stored.importOriginalCategory == metadata.originalCategory
            && stored.importOriginalTimestamp == metadata.originalTimestamp
            && stored.importOriginalAmount == metadata.originalAmount
            && stored.importOriginalAccount == metadata.originalAccount
            && stored.importOriginalBook == metadata.originalBook
            && stored.importOriginalCurrency == metadata.originalCurrency
            && stored.importOriginalNote == metadata.originalNote
    }

    private static func nextSortOrder(
        after maximum: inout Int,
        entity: String
    ) throws -> Int {
        let result = maximum.addingReportingOverflow(1)
        guard !result.overflow else {
            throw LedgerMeowImportStorageError.sortOrderOverflow(entity: entity)
        }
        maximum = result.partialValue
        return maximum
    }

    private static func decimalTotal(
        _ records: [LedgerMeowImportPreparedRecord]
    ) -> Decimal {
        records.reduce(into: Decimal.zero) { total, prepared in
            total += Decimal(prepared.record.amount.minorUnits)
        }
    }

    func mergeFolderSnapshots(
        _ snapshots: [LedgerFolderSnapshot],
        deviceID: UUID,
        generatedAt: Date
    ) throws -> LedgerFolderMergeResult {
        do {
            let allBooks = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>())
            let allCategories = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.CategoryRecord>())
            let allEntries = try modelContext.fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())

            let bookRecords = canonicalRecords(allBooks, preferredBy: Self.preferredBook)
            let categoryRecords = canonicalRecords(allCategories, preferredBy: Self.preferredCategory)
            let entryRecords = canonicalRecords(allEntries, preferredBy: Self.preferredEntry)

            var books = Dictionary(uniqueKeysWithValues: bookRecords.map {
                ($0.id, LedgerFolderCandidate(record: LedgerFolderSnapshot.Book($0), sourceDeviceID: deviceID))
            })
            var categories = Dictionary(uniqueKeysWithValues: categoryRecords.map {
                ($0.id, LedgerFolderCandidate(record: LedgerFolderSnapshot.Category($0), sourceDeviceID: deviceID))
            })
            var entries = Dictionary(uniqueKeysWithValues: entryRecords.map {
                ($0.id, LedgerFolderCandidate(record: LedgerFolderSnapshot.Entry($0), sourceDeviceID: deviceID))
            })

            for snapshot in snapshots.sorted(by: { $0.deviceID.uuidString < $1.deviceID.uuidString }) {
                merge(snapshot.books, sourceDeviceID: snapshot.deviceID, into: &books)
                merge(snapshot.categories, sourceDeviceID: snapshot.deviceID, into: &categories)
                merge(snapshot.entries, sourceDeviceID: snapshot.deviceID, into: &entries)
            }

            let bookRecordsByID = Dictionary(uniqueKeysWithValues: bookRecords.map { ($0.id, $0) })
            let categoryRecordsByID = Dictionary(uniqueKeysWithValues: categoryRecords.map { ($0.id, $0) })
            let entryRecordsByID = Dictionary(uniqueKeysWithValues: entryRecords.map { ($0.id, $0) })
            var importedRecordCount = 0

            for candidate in books.values {
                if let record = bookRecordsByID[candidate.record.id] {
                    guard LedgerFolderSnapshot.Book(record) != candidate.record else { continue }
                    candidate.record.apply(to: record)
                } else {
                    let value = candidate.record
                    modelContext.insert(LedgerSchemaV3.BookRecord(
                        id: value.id,
                        name: value.name,
                        sortOrder: value.sortOrder,
                        createdAt: value.createdAt,
                        updatedAt: value.updatedAt,
                        deletedAt: value.deletedAt
                    ))
                }
                importedRecordCount += 1
            }
            for candidate in categories.values {
                if let record = categoryRecordsByID[candidate.record.id] {
                    guard LedgerFolderSnapshot.Category(record) != candidate.record else { continue }
                    candidate.record.apply(to: record)
                } else {
                    let value = candidate.record
                    modelContext.insert(LedgerSchemaV3.CategoryRecord(
                        id: value.id,
                        name: value.name,
                        kindRawValue: value.kindRawValue,
                        sortOrder: value.sortOrder,
                        createdAt: value.createdAt,
                        updatedAt: value.updatedAt,
                        deletedAt: value.deletedAt
                    ))
                }
                importedRecordCount += 1
            }
            for candidate in entries.values {
                if let record = entryRecordsByID[candidate.record.id] {
                    guard LedgerFolderSnapshot.Entry(record) != candidate.record else { continue }
                    candidate.record.apply(to: record)
                } else {
                    let value = candidate.record
                    modelContext.insert(LedgerSchemaV3.EntryRecord(
                        id: value.id,
                        bookID: value.bookID,
                        categoryID: value.categoryID,
                        kindRawValue: value.kindRawValue,
                        amountMinorUnits: value.amountMinorUnits,
                        occurredAt: value.occurredAt,
                        note: value.note,
                        sourceRawValue: value.sourceRawValue,
                        importFormatRawValue: value.importFormatRawValue,
                        importDeduplicationKey: value.importDeduplicationKey,
                        importOriginalCategory: value.importOriginalCategory,
                        importOriginalTimestamp: value.importOriginalTimestamp,
                        importOriginalAmount: value.importOriginalAmount,
                        importOriginalAccount: value.importOriginalAccount,
                        importOriginalBook: value.importOriginalBook,
                        importOriginalCurrency: value.importOriginalCurrency,
                        importOriginalNote: value.importOriginalNote,
                        scheduledRuleID: value.scheduledRuleID,
                        scheduledYear: value.scheduledYear,
                        scheduledMonth: value.scheduledMonth,
                        scheduledOccurrenceKey: value.scheduledOccurrenceKey,
                        createdAt: value.createdAt,
                        updatedAt: value.updatedAt,
                        deletedAt: value.deletedAt
                    ))
                }
                importedRecordCount += 1
            }

            try validateMergedRecords(
                books: books.values.map(\.record),
                categories: categories.values.map(\.record),
                entries: entries.values.map(\.record)
            )
            if modelContext.hasChanges { try modelContext.save() }

            let snapshot = LedgerFolderSnapshot(
                formatVersion: LedgerFolderSnapshot.currentFormatVersion,
                schemaVersion: LocalLedgerStore.currentSchemaVersion,
                deviceID: deviceID,
                generatedAt: generatedAt,
                books: books.values.map(\.record).sorted { $0.id.uuidString < $1.id.uuidString },
                categories: categories.values.map(\.record).sorted { $0.id.uuidString < $1.id.uuidString },
                entries: entries.values.map(\.record).sorted { $0.id.uuidString < $1.id.uuidString }
            )
            return LedgerFolderMergeResult(
                importedRecordCount: importedRecordCount,
                snapshot: snapshot
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func canonicalRecords<Record: PersistentModel>(
        _ records: [Record],
        preferredBy: (Record, Record) -> Bool
    ) -> [Record] where Record: AnyObject {
        var canonical: [Record] = []
        for values in Dictionary(grouping: records, by: { recordID($0) }).values {
            let ordered = values.sorted(by: preferredBy)
            canonical.append(ordered[0])
            for duplicate in ordered.dropFirst() { modelContext.delete(duplicate) }
        }
        return canonical
    }

    private func recordID<Record: PersistentModel>(_ record: Record) -> UUID {
        switch record {
        case let book as LedgerSchemaV3.BookRecord: book.id
        case let category as LedgerSchemaV3.CategoryRecord: category.id
        case let entry as LedgerSchemaV3.EntryRecord: entry.id
        default: preconditionFailure("Unsupported ledger record type")
        }
    }

    private func merge<Record: LedgerFolderVersionedRecord>(
        _ incoming: [Record],
        sourceDeviceID: UUID,
        into records: inout [UUID: LedgerFolderCandidate<Record>]
    ) {
        for record in incoming {
            let candidate = LedgerFolderCandidate(record: record, sourceDeviceID: sourceDeviceID)
            if let current = records[record.id] {
                if Self.prefers(candidate, over: current) { records[record.id] = candidate }
            } else {
                records[record.id] = candidate
            }
        }
    }

    private static func prefers<Record: LedgerFolderVersionedRecord>(
        _ candidate: LedgerFolderCandidate<Record>,
        over current: LedgerFolderCandidate<Record>
    ) -> Bool {
        let candidateDate = max(candidate.record.updatedAt, candidate.record.deletedAt ?? .distantPast)
        let currentDate = max(current.record.updatedAt, current.record.deletedAt ?? .distantPast)
        if candidateDate != currentDate { return candidateDate > currentDate }
        if (candidate.record.deletedAt != nil) != (current.record.deletedAt != nil) {
            return candidate.record.deletedAt != nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let candidateData = try? encoder.encode(candidate.record)
        let currentData = try? encoder.encode(current.record)
        if candidateData != currentData {
            return currentData.map { candidateData?.lexicographicallyPrecedes($0) == false } ?? true
        }
        return candidate.sourceDeviceID.uuidString > current.sourceDeviceID.uuidString
    }

    private func validateMergedRecords(
        books: [LedgerFolderSnapshot.Book],
        categories: [LedgerFolderSnapshot.Category],
        entries: [LedgerFolderSnapshot.Entry]
    ) throws {
        let bookIDs = Set(books.map(\.id))
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for entry in entries {
            guard bookIDs.contains(entry.bookID),
                  let category = categoriesByID[entry.categoryID],
                  category.kindRawValue == entry.kindRawValue
            else {
                throw LedgerFolderSyncError.invalidSnapshot(
                    file: "合并结果",
                    reason: "账目引用或收支类型冲突"
                )
            }
        }
    }

    private func validate(_ draft: LedgerEntryDraft) throws {
        try LedgerValidation.validate(draft, books: activeBooks(), categories: activeCategories())
    }

    private func findEntry(
        id: UUID,
        includesDeleted: Bool = false
    ) throws -> LedgerSchemaV3.EntryRecord? {
        var descriptor = FetchDescriptor<LedgerSchemaV3.EntryRecord>()
        descriptor.predicate = includesDeleted
            ? #Predicate { $0.id == id }
            : #Predicate { $0.id == id && $0.deletedAt == nil }
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func findBook(
        id: UUID,
        includesDeleted: Bool = false
    ) throws -> LedgerSchemaV3.BookRecord? {
        var descriptor = FetchDescriptor<LedgerSchemaV3.BookRecord>()
        descriptor.predicate = includesDeleted
            ? #Predicate { $0.id == id }
            : #Predicate { $0.id == id && $0.deletedAt == nil }
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func reconcileDuplicates(in context: ModelContext) throws {
        let books = try context.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>())
        for duplicates in Dictionary(grouping: books, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredBook)
            for record in ordered.dropFirst() { context.delete(record) }
        }

        let categories = try context.fetch(FetchDescriptor<LedgerSchemaV3.CategoryRecord>())
        for duplicates in Dictionary(grouping: categories, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredCategory)
            for record in ordered.dropFirst() { context.delete(record) }
        }

        let entries = try context.fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())
        for duplicates in Dictionary(grouping: entries, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredEntry)
            for record in ordered.dropFirst() { context.delete(record) }
        }

        let metadata = try context.fetch(FetchDescriptor<LedgerSchemaV3.StoreMetadata>())
        for duplicates in Dictionary(grouping: metadata, by: \.key).values where duplicates.count > 1 {
            let ordered = duplicates.sorted {
                String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
            }
            for record in ordered.dropFirst() { context.delete(record) }
        }

        if context.hasChanges { try context.save() }
    }

    private func reconcileDuplicates() throws {
        try Self.reconcileDuplicates(in: modelContext)
    }

    /// Seed upgrades only require unique books, categories and metadata. Entries are omitted
    /// here so opening a large current store does not perform a full history scan.
    private static func reconcileBootstrapRecords(in context: ModelContext) throws {
        let books = try context.fetch(FetchDescriptor<LedgerSchemaV3.BookRecord>())
        for duplicates in Dictionary(grouping: books, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredBook)
            for record in ordered.dropFirst() { context.delete(record) }
        }
        let categories = try context.fetch(FetchDescriptor<LedgerSchemaV3.CategoryRecord>())
        for duplicates in Dictionary(grouping: categories, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredCategory)
            for record in ordered.dropFirst() { context.delete(record) }
        }
        let metadata = try context.fetch(FetchDescriptor<LedgerSchemaV3.StoreMetadata>())
        for duplicates in Dictionary(grouping: metadata, by: \.key).values where duplicates.count > 1 {
            let ordered = duplicates.sorted {
                String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
            }
            for record in ordered.dropFirst() { context.delete(record) }
        }
        if context.hasChanges { try context.save() }
    }

    private static func preferredBook(
        _ left: LedgerSchemaV3.BookRecord,
        _ right: LedgerSchemaV3.BookRecord
    ) -> Bool {
        let leftDate = max(left.updatedAt, left.deletedAt ?? .distantPast)
        let rightDate = max(right.updatedAt, right.deletedAt ?? .distantPast)
        if leftDate != rightDate { return leftDate > rightDate }
        if (left.deletedAt != nil) != (right.deletedAt != nil) { return left.deletedAt != nil }
        if left.name != right.name { return left.name < right.name }
        if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
        return String(describing: left.persistentModelID) < String(describing: right.persistentModelID)
    }

    private static func preferredCategory(
        _ left: LedgerSchemaV3.CategoryRecord,
        _ right: LedgerSchemaV3.CategoryRecord
    ) -> Bool {
        let leftDate = max(left.updatedAt, left.deletedAt ?? .distantPast)
        let rightDate = max(right.updatedAt, right.deletedAt ?? .distantPast)
        if leftDate != rightDate { return leftDate > rightDate }
        if (left.deletedAt != nil) != (right.deletedAt != nil) { return left.deletedAt != nil }
        if left.name != right.name { return left.name < right.name }
        if left.kindRawValue != right.kindRawValue { return left.kindRawValue < right.kindRawValue }
        if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
        return String(describing: left.persistentModelID) < String(describing: right.persistentModelID)
    }

    private static func preferredEntry(
        _ left: LedgerSchemaV3.EntryRecord,
        _ right: LedgerSchemaV3.EntryRecord
    ) -> Bool {
        let leftDate = max(left.updatedAt, left.deletedAt ?? .distantPast)
        let rightDate = max(right.updatedAt, right.deletedAt ?? .distantPast)
        if leftDate != rightDate { return leftDate > rightDate }
        if (left.deletedAt != nil) != (right.deletedAt != nil) { return left.deletedAt != nil }
        if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
        if left.bookID != right.bookID { return left.bookID.uuidString < right.bookID.uuidString }
        if left.categoryID != right.categoryID { return left.categoryID.uuidString < right.categoryID.uuidString }
        if left.kindRawValue != right.kindRawValue { return left.kindRawValue < right.kindRawValue }
        if left.occurredAt != right.occurredAt { return left.occurredAt < right.occurredAt }
        if left.note != right.note { return left.note < right.note }
        if left.sourceRawValue != right.sourceRawValue { return left.sourceRawValue < right.sourceRawValue }
        if left.amountMinorUnits != right.amountMinorUnits {
            return left.amountMinorUnits < right.amountMinorUnits
        }
        let leftImportValues = importMetadataSortValues(left)
        let rightImportValues = importMetadataSortValues(right)
        if leftImportValues != rightImportValues {
            return leftImportValues.lexicographicallyPrecedes(rightImportValues)
        }
        return String(describing: left.persistentModelID) < String(describing: right.persistentModelID)
    }

    private static func importMetadataSortValues(
        _ record: LedgerSchemaV3.EntryRecord
    ) -> [String] {
        [
            record.importFormatRawValue,
            record.importDeduplicationKey,
            record.importOriginalCategory,
            record.importOriginalTimestamp,
            record.importOriginalAmount,
            record.importOriginalAccount,
            record.importOriginalBook,
            record.importOriginalCurrency,
            record.importOriginalNote,
            record.scheduledRuleID?.uuidString,
            record.scheduledYear.map(String.init),
            record.scheduledMonth.map(String.init),
            record.scheduledOccurrenceKey,
        ].map { $0 ?? "" }
    }

    private func save<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            let value = try operation()
            try modelContext.save()
            return value
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func entry(from record: LedgerSchemaV3.EntryRecord) throws -> LedgerEntry {
        guard let kind = LedgerEntryKind(rawValue: record.kindRawValue),
              let source = LedgerEntrySource(rawValue: record.sourceRawValue),
              record.createdAt.timeIntervalSinceReferenceDate.isFinite,
              record.updatedAt.timeIntervalSinceReferenceDate.isFinite
        else { throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "来源、类型或时间") }
        let importMetadata = try importMetadata(from: record)
        let scheduledOccurrence = try scheduledOccurrence(from: record)
        let draft = LedgerEntryDraft(
            bookID: record.bookID,
            categoryID: record.categoryID,
            kind: kind,
            amount: try LedgerAmount(minorUnits: record.amountMinorUnits),
            date: record.occurredAt,
            note: record.note,
            source: source,
            importMetadata: importMetadata,
            scheduledOccurrence: scheduledOccurrence
        )
        return LedgerEntry(id: record.id, draft: draft, createdAt: record.createdAt, updatedAt: record.updatedAt)
    }

    private static func validateImportMetadata(_ draft: LedgerEntryDraft) throws {
        if draft.importMetadata == nil {
            guard draft.source != .meowLedgerImport else {
                throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "导入元数据")
            }
            return
        }
        guard draft.source == .meowLedgerImport,
              draft.importMetadata?.deduplicationKey.isEmpty == false
        else {
            throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "导入元数据")
        }
    }

    private static func validateScheduledMetadata(_ draft: LedgerEntryDraft) throws {
        guard let occurrence = draft.scheduledOccurrence else {
            guard draft.source != .scheduled else {
                throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "定时 occurrence")
            }
            return
        }
        guard draft.source == .scheduled,
              draft.importMetadata == nil,
              !occurrence.occurrenceKey.isEmpty
        else {
            throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "定时 occurrence")
        }
    }

    private static func importMetadata(
        from record: LedgerSchemaV3.EntryRecord
    ) throws -> LedgerEntryImportMetadata? {
        let values = [
            record.importFormatRawValue,
            record.importDeduplicationKey,
            record.importOriginalCategory,
            record.importOriginalTimestamp,
            record.importOriginalAmount,
            record.importOriginalAccount,
            record.importOriginalBook,
            record.importOriginalCurrency,
            record.importOriginalNote,
        ]
        if values.allSatisfy({ $0 == nil }) {
            guard record.sourceRawValue != LedgerEntrySource.meowLedgerImport.rawValue else {
                throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "导入元数据")
            }
            return nil
        }
        guard values.allSatisfy({ $0 != nil }),
              record.sourceRawValue == LedgerEntrySource.meowLedgerImport.rawValue,
              let formatRawValue = record.importFormatRawValue,
              let format = LedgerEntryImportFormat(rawValue: formatRawValue),
              let deduplicationKey = record.importDeduplicationKey,
              !deduplicationKey.isEmpty,
              let originalCategory = record.importOriginalCategory,
              let originalTimestamp = record.importOriginalTimestamp,
              let originalAmount = record.importOriginalAmount,
              let originalAccount = record.importOriginalAccount,
              let originalBook = record.importOriginalBook,
              let originalCurrency = record.importOriginalCurrency,
              let originalNote = record.importOriginalNote
        else {
            throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "导入元数据")
        }
        return LedgerEntryImportMetadata(
            format: format,
            deduplicationKey: deduplicationKey,
            originalCategory: originalCategory,
            originalTimestamp: originalTimestamp,
            originalAmount: originalAmount,
            originalAccount: originalAccount,
            originalBook: originalBook,
            originalCurrency: originalCurrency,
            originalNote: originalNote
        )
    }

    private static func scheduledOccurrence(
        from record: LedgerSchemaV3.EntryRecord
    ) throws -> LedgerScheduledOccurrenceMetadata? {
        let valuesPresent = [
            record.scheduledRuleID != nil,
            record.scheduledYear != nil,
            record.scheduledMonth != nil,
            record.scheduledOccurrenceKey != nil,
        ]
        if valuesPresent.allSatisfy({ !$0 }) {
            guard record.sourceRawValue != LedgerEntrySource.scheduled.rawValue else {
                throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "定时 occurrence")
            }
            return nil
        }
        guard valuesPresent.allSatisfy({ $0 }),
              record.sourceRawValue == LedgerEntrySource.scheduled.rawValue,
              record.importFormatRawValue == nil,
              let ruleID = record.scheduledRuleID,
              let year = record.scheduledYear,
              let month = record.scheduledMonth,
              let occurrenceKey = record.scheduledOccurrenceKey,
              let yearMonth = try? LedgerYearMonth(year: year, month: month)
        else {
            throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "定时 occurrence")
        }
        let metadata = LedgerScheduledOccurrenceMetadata(ruleID: ruleID, month: yearMonth)
        guard metadata.occurrenceKey == occurrenceKey else {
            throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "定时 occurrence")
        }
        return metadata
    }
}
