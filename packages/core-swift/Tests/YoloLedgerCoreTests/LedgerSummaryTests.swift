import Foundation
import XCTest
import YoloLedgerCore

final class LedgerSummaryTests: XCTestCase {
    private func entry(_ kind: LedgerEntryKind, minorUnits: Int64, date: Date = Date(timeIntervalSince1970: 1_798_000_000)) throws -> LedgerEntry {
        let category = LedgerSeedData.categories.first { $0.kind == kind }!
        let draft = LedgerEntryDraft(
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: category.id,
            kind: kind,
            amount: try LedgerAmount(minorUnits: minorUnits),
            date: date
        )
        return LedgerEntry(id: UUID(), draft: draft, createdAt: date, updatedAt: date)
    }

    func testEmptySummaryAndExactIncomeExpenseBalance() throws {
        XCTAssertEqual(try LedgerSummary(entries: []), .zero)
        let summary = try LedgerSummary(entries: [
            entry(.expense, minorUnits: 10),
            entry(.expense, minorUnits: 20),
            entry(.income, minorUnits: 100),
        ])
        XCTAssertEqual(summary.expenseMinorUnits, 30)
        XCTAssertEqual(summary.incomeMinorUnits, 100)
        XCTAssertEqual(summary.balanceMinorUnits, 70)
        XCTAssertEqual(summary.entryCount, 3)
        XCTAssertEqual(LedgerAmount.format(minorUnits: summary.expenseMinorUnits), "0.30")
    }

    func testExpenseOnlySummaryMayHaveNegativeBalance() throws {
        let summary = try LedgerSummary(entries: [entry(.expense, minorUnits: 1201)])
        XCTAssertEqual(summary.balanceMinorUnits, -1201)
        XCTAssertEqual(LedgerAmount.format(minorUnits: summary.balanceMinorUnits), "-12.01")
    }

    func testDateFilteringCountsOnlyHalfOpenRangeWithoutMutatingEntries() throws {
        let start = Date(timeIntervalSince1970: 1_798_000_000)
        let end = start.addingTimeInterval(86400)
        let entries = try [
            entry(.income, minorUnits: 100, date: start.addingTimeInterval(-1)),
            entry(.income, minorUnits: 200, date: start),
            entry(.expense, minorUnits: 50, date: end.addingTimeInterval(-1)),
            entry(.expense, minorUnits: 1000, date: end),
        ]
        let summary = try LedgerSummary(entries: entries, dateRange: LedgerDateRange(start: start, end: end))
        XCTAssertEqual(summary.incomeMinorUnits, 200)
        XCTAssertEqual(summary.expenseMinorUnits, 50)
        XCTAssertEqual(summary.balanceMinorUnits, 150)
        XCTAssertEqual(summary.entryCount, 2)
        XCTAssertEqual(entries.count, 4)
    }

    func testIncomeAndExpenseOverflowEachThrowInsteadOfWrapping() throws {
        for kind in LedgerEntryKind.allCases {
            let entries = try [entry(kind, minorUnits: .max), entry(kind, minorUnits: 1)]
            XCTAssertThrowsError(try LedgerSummary(entries: entries)) { error in
                XCTAssertEqual(error as? LedgerError, .summaryOverflow)
            }
        }
    }

    func testMaximumTotalsCanOffsetWithoutFalseOverflow() throws {
        let summary = try LedgerSummary(entries: [entry(.income, minorUnits: .max), entry(.expense, minorUnits: .max)])
        XCTAssertEqual(summary.incomeMinorUnits, .max)
        XCTAssertEqual(summary.expenseMinorUnits, .max)
        XCTAssertEqual(summary.balanceMinorUnits, 0)
    }

    func testInvalidEntryDateIsReported() throws {
        let invalid = try entry(.expense, minorUnits: 1, date: Date(timeIntervalSinceReferenceDate: .infinity))
        XCTAssertThrowsError(try LedgerSummary(entries: [invalid])) { error in
            XCTAssertEqual(error as? LedgerError, .invalidDate)
        }
    }
}
