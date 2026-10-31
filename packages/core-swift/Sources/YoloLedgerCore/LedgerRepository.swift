import Foundation

public enum LedgerSyncState: Equatable, Sendable {
    case localOnly
    case checking
    case available(lastSuccessfulSync: Date?)
    case syncing
    case unavailable(reason: String)
    case error(message: String)
}

/// Shared ledger contract. Values crossing isolation boundaries are Sendable.
public protocol LedgerRepository: LedgerBookRepository {
    func fetchCategories() async throws -> [LedgerCategory]
    /// Returns the selected book's entries, or all entries when bookID is nil.
    /// Results are ordered by date descending, then createdAt descending, then UUID string ascending.
    func fetchEntries(bookID: UUID?) async throws -> [LedgerEntry]
    /// Returns one book's entries inside a half-open local-calendar interval.
    /// Concrete stores should push this filter into the database instead of loading every entry.
    func fetchEntries(bookID: UUID, dateRange: LedgerDateRange) async throws -> [LedgerEntry]
    /// Returns up to `limit` distinct non-empty notes for one category in FIFO display order.
    func fetchRecentNotes(categoryID: UUID, limit: Int) async throws -> [String]

    /// The caller can retain id across retries; an existing id throws duplicateIdentifier.
    func createEntry(_ draft: LedgerEntryDraft, id: UUID) async throws -> LedgerEntry
    /// Preserves the original id, createdAt and source; updates updatedAt after validation.
    func updateEntry(id: UUID, draft: LedgerEntryDraft) async throws -> LedgerEntry
    /// Throws entryNotFound if the record is absent.
    func deleteEntry(id: UUID) async throws

    func createBook(name: String, id: UUID) async throws -> LedgerBook
    /// Keeps the book identity and any referencing entries unchanged.
    func renameBook(id: UUID, name: String) async throws -> LedgerBook

    /// Emits after the persistent store imports remote changes or its sync state changes.
    func updates() -> AsyncStream<Void>
    func currentSyncState() -> LedgerSyncState
}

public extension LedgerRepository {
    func fetchEntries() async throws -> [LedgerEntry] {
        try await fetchEntries(bookID: nil)
    }

    func fetchEntries(bookID: UUID, dateRange: LedgerDateRange) async throws -> [LedgerEntry] {
        try await fetchEntries(bookID: bookID).filter { dateRange.contains($0.date) }
    }

    func fetchRecentNotes(categoryID: UUID, limit: Int) async throws -> [String] {
        guard limit > 0 else { return [] }
        let candidates = try await fetchEntries(bookID: nil)
            .filter { $0.categoryID == categoryID }
            .sorted { left, right in
                if left.updatedAt != right.updatedAt { return left.updatedAt < right.updatedAt }
                if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
                if left.date != right.date { return left.date < right.date }
                return left.id.uuidString < right.id.uuidString
            }
        var seen = Set<String>()
        var notes: [String] = []
        for entry in candidates {
            let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func createEntry(_ draft: LedgerEntryDraft) async throws -> LedgerEntry {
        try await createEntry(draft, id: UUID())
    }

    func createBook(name: String) async throws -> LedgerBook {
        try await createBook(name: name, id: UUID())
    }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }

    func currentSyncState() -> LedgerSyncState { .localOnly }
}
