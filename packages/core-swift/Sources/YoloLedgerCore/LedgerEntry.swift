import Foundation

public enum LedgerEntryKind: String, CaseIterable, Codable, Sendable {
    case expense
    case income
}

public enum LedgerEntrySource: String, Codable, Sendable {
    case manual
    case screenshotShortcut
    case meowLedgerImport
    case scheduled
}

public enum LedgerEntryImportFormat: String, Codable, Sendable {
    case meowLedgerCSVV1 = "meow-ledger-csv-v1"
}

/// Lossless source metadata retained after an imported row becomes a ledger entry.
public struct LedgerEntryImportMetadata: Equatable, Codable, Sendable {
    public let format: LedgerEntryImportFormat
    public let deduplicationKey: String
    public let originalCategory: String
    public let originalTimestamp: String
    public let originalAmount: String
    public let originalAccount: String
    public let originalBook: String
    public let originalCurrency: String
    public let originalNote: String

    public init(
        format: LedgerEntryImportFormat,
        deduplicationKey: String,
        originalCategory: String,
        originalTimestamp: String,
        originalAmount: String,
        originalAccount: String,
        originalBook: String,
        originalCurrency: String,
        originalNote: String
    ) {
        self.format = format
        self.deduplicationKey = deduplicationKey
        self.originalCategory = originalCategory
        self.originalTimestamp = originalTimestamp
        self.originalAmount = originalAmount
        self.originalAccount = originalAccount
        self.originalBook = originalBook
        self.originalCurrency = originalCurrency
        self.originalNote = originalNote
    }
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
    public let importMetadata: LedgerEntryImportMetadata?
    public let scheduledOccurrence: LedgerScheduledOccurrenceMetadata?

    public init(
        bookID: UUID,
        categoryID: UUID,
        kind: LedgerEntryKind,
        amount: LedgerAmount,
        date: Date,
        note: String = "",
        source: LedgerEntrySource = .manual,
        importMetadata: LedgerEntryImportMetadata? = nil,
        scheduledOccurrence: LedgerScheduledOccurrenceMetadata? = nil
    ) {
        self.bookID = bookID
        self.categoryID = categoryID
        self.kind = kind
        self.amount = amount
        self.date = date
        self.note = note
        self.source = source
        self.importMetadata = importMetadata
        self.scheduledOccurrence = scheduledOccurrence
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
    public let importMetadata: LedgerEntryImportMetadata?
    public let scheduledOccurrence: LedgerScheduledOccurrenceMetadata?
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
        self.importMetadata = draft.importMetadata
        self.scheduledOccurrence = draft.scheduledOccurrence
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
            source: source,
            importMetadata: importMetadata,
            scheduledOccurrence: scheduledOccurrence
        )
    }
}
