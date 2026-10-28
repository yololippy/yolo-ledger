import Foundation

public enum LedgerValidation {
    public static func normalizedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LedgerError.emptyName }
        return name
    }

    /// Repositories call this before both create and update, using current stored references.
    public static func validate(
        _ draft: LedgerEntryDraft,
        books: [LedgerBook],
        categories: [LedgerCategory]
    ) throws {
        guard books.contains(where: { $0.id == draft.bookID }) else {
            throw LedgerError.bookNotFound(draft.bookID)
        }
        guard let category = categories.first(where: { $0.id == draft.categoryID }) else {
            throw LedgerError.categoryNotFound(draft.categoryID)
        }
        guard category.kind == draft.kind else { throw LedgerError.categoryKindMismatch }
        guard draft.date.timeIntervalSinceReferenceDate.isFinite else { throw LedgerError.invalidDate }
    }
}
