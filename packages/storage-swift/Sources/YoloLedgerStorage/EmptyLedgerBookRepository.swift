import YoloLedgerCore

/// An empty data adapter for assembling the M1 app skeleton.
/// This adapter does not read or persist ledger books.
public struct EmptyLedgerBookRepository: LedgerBookRepository {
    public init() {}

    public func fetchBooks() async throws -> [LedgerBook] {
        []
    }
}
