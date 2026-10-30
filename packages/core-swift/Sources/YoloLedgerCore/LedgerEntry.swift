import Foundation

public enum LedgerEntryKind: String, CaseIterable, Codable, Sendable {
    case expense
    case income
}

public enum LedgerEntrySource: String, Codable, Sendable {
    case manual
    case screenshotShortcut
}

public struct LedgerCategory: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: LedgerEntryKind

    public init(id: UUID, name: String, kind: LedgerEntryKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Editable content. The repository owns record identity and audit timestamps.
public struct LedgerEntryDraft: Equatable, Sendable {
    public let bookID: UUID
    public let categoryID: UUID
    public let kind: LedgerEntryKind
    public let amount: LedgerAmount
    public let date: Date
    public let note: String
    public let source: LedgerEntrySource

    public init(
        bookID: UUID,
        categoryID: UUID,
        kind: LedgerEntryKind,
        amount: LedgerAmount,
        date: Date,
        note: String = "",
        source: LedgerEntrySource = .manual
    ) {
        self.bookID = bookID
        self.categoryID = categoryID
        self.kind = kind
        self.amount = amount
        self.date = date
        self.note = note
        self.source = source
    }
}

public struct LedgerEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let categoryID: UUID
    public let kind: LedgerEntryKind
    public let amount: LedgerAmount
    public let date: Date
    public let note: String
    public let source: LedgerEntrySource
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, draft: LedgerEntryDraft, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.bookID = draft.bookID
        self.categoryID = draft.categoryID
        self.kind = draft.kind
        self.amount = draft.amount
        self.date = draft.date
        self.note = draft.note
        self.source = draft.source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var draft: LedgerEntryDraft {
        LedgerEntryDraft(
            bookID: bookID,
            categoryID: categoryID,
            kind: kind,
            amount: amount,
            date: date,
            note: note,
            source: source
        )
    }
}
