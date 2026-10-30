import Foundation
import SwiftData
import YoloLedgerCore

/// A local, disk-backed repository. Create one instance per active app store.
public struct SwiftDataLedgerRepository: LedgerRepository {
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
        .appendingPathComponent("YoloLedger", isDirectory: true)
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
}

private actor LedgerStoreActor: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer

    init(storeURL: URL, syncMode: LedgerSyncMode) throws {
        let container = try LocalLedgerStore.makeContainer(at: storeURL, syncMode: syncMode)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try Self.reconcileDuplicates(in: context)
        try LedgerSeedBootstrap.initialize(in: context)
        try Self.reconcileDuplicates(in: context)
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    func fetchBooks() throws -> [LedgerBook] {
        try reconcileDuplicates()
        return try activeBooks()
    }

    private func activeBooks() throws -> [LedgerBook] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>(
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
        try reconcileDuplicates()
        return try activeCategories()
    }

    private func activeCategories() throws -> [LedgerCategory] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>(
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
        try reconcileDuplicates()
        let books = try activeBooks()
        let categories = try activeCategories()
        var descriptor = FetchDescriptor<LedgerSchemaV1.EntryRecord>(
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

    func createEntry(_ draft: LedgerEntryDraft, id: UUID) throws -> LedgerEntry {
        try reconcileDuplicates()
        guard try findEntry(id: id, includesDeleted: true) == nil else {
            throw LedgerError.duplicateIdentifier(id)
        }
        try validate(draft)
        let now = Date()
        let record = LedgerSchemaV1.EntryRecord(
            id: id,
            bookID: draft.bookID,
            categoryID: draft.categoryID,
            kindRawValue: draft.kind.rawValue,
            amountMinorUnits: draft.amount.minorUnits,
            occurredAt: draft.date,
            note: draft.note,
            sourceRawValue: draft.source.rawValue,
            createdAt: now,
            updatedAt: now
        )
        return try save {
            modelContext.insert(record)
            return try Self.entry(from: record)
        }
    }

    func updateEntry(id: UUID, draft: LedgerEntryDraft) throws -> LedgerEntry {
        try reconcileDuplicates()
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
        try reconcileDuplicates()
        guard let record = try findEntry(id: id) else { throw LedgerError.entryNotFound(id) }
        try save {
            let now = Date()
            record.deletedAt = now
            record.updatedAt = max(now, record.updatedAt)
        }
    }

    func createBook(name: String, id: UUID) throws -> LedgerBook {
        try reconcileDuplicates()
        let normalizedName = try LedgerValidation.normalizedName(name)
        guard try findBook(id: id, includesDeleted: true) == nil else {
            throw LedgerError.duplicateIdentifier(id)
        }
        let records = try modelContext.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        let (order, overflow) = (records.map(\.sortOrder).max() ?? -1).addingReportingOverflow(1)
        guard !overflow else {
            throw LedgerStorageError.invalidStoredValue(entity: "账本", field: "排序")
        }
        let record = LedgerSchemaV1.BookRecord(id: id, name: normalizedName, sortOrder: order)
        return try save {
            modelContext.insert(record)
            return LedgerBook(id: record.id, name: record.name)
        }
    }

    func renameBook(id: UUID, name: String) throws -> LedgerBook {
        try reconcileDuplicates()
        let normalizedName = try LedgerValidation.normalizedName(name)
        guard let record = try findBook(id: id) else { throw LedgerError.bookNotFound(id) }
        return try save {
            record.name = normalizedName
            record.updatedAt = max(Date(), record.updatedAt)
            return LedgerBook(id: record.id, name: record.name)
        }
    }

    private func validate(_ draft: LedgerEntryDraft) throws {
        try LedgerValidation.validate(draft, books: activeBooks(), categories: activeCategories())
    }

    private func findEntry(
        id: UUID,
        includesDeleted: Bool = false
    ) throws -> LedgerSchemaV1.EntryRecord? {
        var descriptor = FetchDescriptor<LedgerSchemaV1.EntryRecord>()
        descriptor.predicate = includesDeleted
            ? #Predicate { $0.id == id }
            : #Predicate { $0.id == id && $0.deletedAt == nil }
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func findBook(
        id: UUID,
        includesDeleted: Bool = false
    ) throws -> LedgerSchemaV1.BookRecord? {
        var descriptor = FetchDescriptor<LedgerSchemaV1.BookRecord>()
        descriptor.predicate = includesDeleted
            ? #Predicate { $0.id == id }
            : #Predicate { $0.id == id && $0.deletedAt == nil }
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func reconcileDuplicates() throws {
        try Self.reconcileDuplicates(in: modelContext)
    }

    private static func reconcileDuplicates(in context: ModelContext) throws {
        let books = try context.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
        for duplicates in Dictionary(grouping: books, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredBook)
            for record in ordered.dropFirst() { context.delete(record) }
        }

        let categories = try context.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>())
        for duplicates in Dictionary(grouping: categories, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredCategory)
            for record in ordered.dropFirst() { context.delete(record) }
        }

        let entries = try context.fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>())
        for duplicates in Dictionary(grouping: entries, by: \.id).values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredEntry)
            for record in ordered.dropFirst() { context.delete(record) }
        }

        let metadata = try context.fetch(FetchDescriptor<LedgerSchemaV1.StoreMetadata>())
        for duplicates in Dictionary(grouping: metadata, by: \.key).values where duplicates.count > 1 {
            let ordered = duplicates.sorted {
                String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
            }
            for record in ordered.dropFirst() { context.delete(record) }
        }

        if context.hasChanges { try context.save() }
    }

    private static func preferredBook(
        _ left: LedgerSchemaV1.BookRecord,
        _ right: LedgerSchemaV1.BookRecord
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
        _ left: LedgerSchemaV1.CategoryRecord,
        _ right: LedgerSchemaV1.CategoryRecord
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
        _ left: LedgerSchemaV1.EntryRecord,
        _ right: LedgerSchemaV1.EntryRecord
    ) -> Bool {
        let leftDate = max(left.updatedAt, left.deletedAt ?? .distantPast)
        let rightDate = max(right.updatedAt, right.deletedAt ?? .distantPast)
        if leftDate != rightDate { return leftDate > rightDate }
        if (left.deletedAt != nil) != (right.deletedAt != nil) { return left.deletedAt != nil }
        if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
        if left.note != right.note { return left.note < right.note }
        if left.amountMinorUnits != right.amountMinorUnits {
            return left.amountMinorUnits < right.amountMinorUnits
        }
        return String(describing: left.persistentModelID) < String(describing: right.persistentModelID)
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

    private static func entry(from record: LedgerSchemaV1.EntryRecord) throws -> LedgerEntry {
        guard let kind = LedgerEntryKind(rawValue: record.kindRawValue),
              let source = LedgerEntrySource(rawValue: record.sourceRawValue),
              record.createdAt.timeIntervalSinceReferenceDate.isFinite,
              record.updatedAt.timeIntervalSinceReferenceDate.isFinite
        else { throw LedgerStorageError.invalidStoredValue(entity: "账目", field: "来源、类型或时间") }
        let draft = LedgerEntryDraft(
            bookID: record.bookID,
            categoryID: record.categoryID,
            kind: kind,
            amount: try LedgerAmount(minorUnits: record.amountMinorUnits),
            date: record.occurredAt,
            note: record.note,
            source: source
        )
        return LedgerEntry(id: record.id, draft: draft, createdAt: record.createdAt, updatedAt: record.updatedAt)
    }
}
