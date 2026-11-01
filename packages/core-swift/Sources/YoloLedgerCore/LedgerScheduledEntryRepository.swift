import Foundation

public enum LedgerScheduledEntryRepositoryError: Error, Equatable, Sendable, LocalizedError {
    case ruleNotFound(UUID)
    case ruleVersionAlreadyExists(ruleID: UUID, effectiveStartMonth: LedgerYearMonth)

    public var errorDescription: String? {
        switch self {
        case .ruleNotFound:
            "定时记账规则不存在。"
        case .ruleVersionAlreadyExists:
            "这个月份已经存在同一规则的版本。"
        }
    }
}

/// Result of one atomic pass over all due scheduled-entry rules.
public struct LedgerScheduledProcessingResult: Equatable, Sendable {
    public let generatedEntries: [LedgerEntry]
    /// Due occurrences skipped because their key was already generated or retained as deleted.
    public let skippedOccurrenceCount: Int

    public init(generatedEntries: [LedgerEntry], skippedOccurrenceCount: Int) {
        self.generatedEntries = generatedEntries
        self.skippedOccurrenceCount = skippedOccurrenceCount
    }

    public var generatedCount: Int { generatedEntries.count }
}

/// Persistence boundary for monthly scheduled entries.
///
/// Implementations retain effective versions for a stable rule ID and atomically persist each
/// generated entry with its occurrence identity. This protocol has no associated types so UI and
/// App composition can inject it as `any LedgerScheduledEntryRepository`.
public protocol LedgerScheduledEntryRepository: Sendable {
    /// Returns the current version of each non-deleted rule for list presentation.
    func fetchScheduledEntryRules() async throws -> [LedgerScheduledEntryRule]

    /// Saves a new effective version. Older versions with the same stable rule ID remain stored.
    @discardableResult
    func saveScheduledEntryRuleVersion(
        _ rule: LedgerScheduledEntryRule
    ) async throws -> LedgerScheduledEntryRule

    /// Disables future generation from `effectiveMonth`; prior occurrences remain unchanged.
    @discardableResult
    func pauseScheduledEntryRule(
        id: UUID,
        effectiveMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule

    /// Creates an enabled version beginning at the explicitly supplied resume month.
    @discardableResult
    func resumeScheduledEntryRule(
        id: UUID,
        effectiveStartMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule

    /// Stops future generation while preserving generated entries and handled occurrence keys.
    func deleteScheduledEntryRule(id: UUID, deletedAt: Date) async throws

    /// Atomically plans and persists all due occurrences across current effective rules.
    func processDueScheduledEntries(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> LedgerScheduledProcessingResult

    /// Returns the earliest next due instant across enabled current rules.
    func nextScheduledEntryDate(
        after now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> Date?
}
