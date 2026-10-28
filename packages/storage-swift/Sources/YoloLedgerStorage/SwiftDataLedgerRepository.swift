import Foundation
import SwiftData
import YoloLedgerCore

/// A local, disk-backed repository. Create one instance per active app store.
public struct SwiftDataLedgerRepository: LedgerRepository {
    public let storeURL: URL
    private let store: LedgerStoreActor

    /// Opens the database, initializes starter choices and applies pending seed-data revisions.
    /// Failures propagate to the caller; no in-memory or destructive fallback is used.
    public init(storeURL: URL) throws {
        self.storeURL = storeURL
        self.store = try LedgerStoreActor(storeURL: storeURL)
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
}

private actor LedgerStoreActor: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer

    init(storeURL: URL) throws {
        let container = try LocalLedgerStore.makeContainer(at: storeURL)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try LedgerSeedBootstrap.initialize(in: context)
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    func fetchBooks() throws -> [LedgerBook] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
            .sorted { left, right in
                left.sortOrder == right.sortOrder
                    ? left.id.uuidString < right.id.uuidString
                    : left.sortOrder < right.sortOrder
            }
            .map { LedgerBook(id: $0.id, name: $0.name) }
    }

    func fetchCategories() throws -> [LedgerCategory] {
        try modelContext.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>())
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
        let books = try fetchBooks()
        let categories = try fetchCategories()
        var descriptor = FetchDescriptor<LedgerSchemaV1.EntryRecord>()
        if let selectedID = bookID {
            guard books.contains(where: { $0.id == selectedID }) else {
                throw LedgerError.bookNotFound(selectedID)
            }
            descriptor.predicate = #Predicate { $0.bookID == selectedID }
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
        guard try findEntry(id: id) == nil else { throw LedgerError.duplicateIdentifier(id) }
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
        try save { modelContext.delete(record) }
    }

    func createBook(name: String, id: UUID) throws -> LedgerBook {
        let normalizedName = try LedgerValidation.normalizedName(name)
        guard try findBook(id: id) == nil else { throw LedgerError.duplicateIdentifier(id) }
        let records = try modelContext.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
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
        let normalizedName = try LedgerValidation.normalizedName(name)
        guard let record = try findBook(id: id) else { throw LedgerError.bookNotFound(id) }
        return try save {
            record.name = normalizedName
            return LedgerBook(id: record.id, name: record.name)
        }
    }

    private func validate(_ draft: LedgerEntryDraft) throws {
        try LedgerValidation.validate(draft, books: fetchBooks(), categories: fetchCategories())
    }

    private func findEntry(id: UUID) throws -> LedgerSchemaV1.EntryRecord? {
        var descriptor = FetchDescriptor<LedgerSchemaV1.EntryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func findBook(id: UUID) throws -> LedgerSchemaV1.BookRecord? {
        var descriptor = FetchDescriptor<LedgerSchemaV1.BookRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
