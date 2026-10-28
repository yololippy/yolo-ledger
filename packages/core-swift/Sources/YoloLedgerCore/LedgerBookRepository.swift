/// Reads ledger books without exposing a concrete persistence framework.
public protocol LedgerBookRepository: Sendable {
    func fetchBooks() async throws -> [LedgerBook]
}
