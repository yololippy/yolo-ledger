import Foundation

/// M2 local CRUD contract. Values crossing isolation boundaries are Sendable.
public protocol LedgerRepository: LedgerBookRepository {
    func fetchCategories() async throws -> [LedgerCategory]
    /// Returns the selected book's entries, or all entries when bookID is nil.
    /// Results are ordered by date descending, then createdAt descending, then UUID string ascending.
    func fetchEntries(bookID: UUID?) async throws -> [LedgerEntry]

    /// The caller can retain id across retries; an existing id throws duplicateIdentifier.
    func createEntry(_ draft: LedgerEntryDraft, id: UUID) async throws -> LedgerEntry
    /// Preserves the original id, createdAt and source; updates updatedAt after validation.
    func updateEntry(id: UUID, draft: LedgerEntryDraft) async throws -> LedgerEntry
    /// Throws entryNotFound if the record is absent.
    func deleteEntry(id: UUID) async throws

    func createBook(name: String, id: UUID) async throws -> LedgerBook
    /// Keeps the book identity and any referencing entries unchanged.
    func renameBook(id: UUID, name: String) async throws -> LedgerBook
}

public extension LedgerRepository {
    func fetchEntries() async throws -> [LedgerEntry] {
        try await fetchEntries(bookID: nil)
    }

    func createEntry(_ draft: LedgerEntryDraft) async throws -> LedgerEntry {
        try await createEntry(draft, id: UUID())
    }

    func createBook(name: String) async throws -> LedgerBook {
        try await createBook(name: name, id: UUID())
    }
}
