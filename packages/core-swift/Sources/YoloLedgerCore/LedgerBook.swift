import Foundation

/// A ledger book available to the app's shared screens.
public struct LedgerBook: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
