import Foundation

/// Exact CNY totals. Income and expense totals are nonnegative; the balance may be negative.
public struct LedgerSummary: Equatable, Sendable {
    public let incomeMinorUnits: Int64
    public let expenseMinorUnits: Int64
    public let balanceMinorUnits: Int64
    public let entryCount: Int

    public static let zero = LedgerSummary()

    public init() {
        incomeMinorUnits = 0
        expenseMinorUnits = 0
        balanceMinorUnits = 0
        entryCount = 0
    }

    /// Pass a selected book's entries and optionally limit totals to a local date range.
    public init(entries: [LedgerEntry], dateRange: LedgerDateRange? = nil) throws {
        var income: Int64 = 0
        var expense: Int64 = 0
        var count = 0
        for entry in entries {
            guard entry.date.timeIntervalSinceReferenceDate.isFinite else {
                throw LedgerError.invalidDate
            }
            if let dateRange, !dateRange.contains(entry.date) { continue }
            switch entry.kind {
            case .income:
                let (total, overflow) = income.addingReportingOverflow(entry.amount.minorUnits)
                guard !overflow else { throw LedgerError.summaryOverflow }
                income = total
            case .expense:
                let (total, overflow) = expense.addingReportingOverflow(entry.amount.minorUnits)
                guard !overflow else { throw LedgerError.summaryOverflow }
                expense = total
            }
            count += 1
        }
        // Both nonnegative totals are at most Int64.max, so their difference is representable.
        incomeMinorUnits = income
        expenseMinorUnits = expense
        balanceMinorUnits = income - expense
        entryCount = count
    }
}
