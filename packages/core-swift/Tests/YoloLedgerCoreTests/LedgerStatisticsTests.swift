import Foundation
import XCTest
import YoloLedgerCore

final class LedgerStatisticsTests: XCTestCase {
    private let bookID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testSnapshotSwitchesKindAndUsesHalfOpenRange() throws {
        let start = date(2026, 1, 1)
        let end = date(2026, 2, 1)
        let expenseCategory = category(1, name: "餐饮", kind: .expense)
        let incomeCategory = category(2, name: "工资", kind: .income)
        let entries = try [
            entry(1, kind: .expense, categoryID: expenseCategory.id, amount: 100, date: start),
            entry(2, kind: .expense, categoryID: expenseCategory.id, amount: 200, date: end.addingTimeInterval(-1)),
            entry(3, kind: .expense, categoryID: expenseCategory.id, amount: 999, date: end),
            entry(4, kind: .income, categoryID: incomeCategory.id, amount: 400, date: start),
        ]
        let range = try LedgerDateRange(start: start, end: end)

        let expenses = try LedgerStatisticsCalculator.snapshot(
            entries: entries,
            categories: [expenseCategory, incomeCategory],
            kind: .expense,
            dateRange: range
        )
        XCTAssertEqual(expenses.totalMinorUnits, 300)
        XCTAssertEqual(expenses.entryCount, 2)
        XCTAssertEqual(expenses.rankedEntries.map(\.id), [uuid(2), uuid(1)])

        let income = try LedgerStatisticsCalculator.snapshot(
            entries: entries,
            categories: [expenseCategory, incomeCategory],
            kind: .income,
            dateRange: range
        )
        XCTAssertEqual(income.totalMinorUnits, 400)
        XCTAssertEqual(income.entryCount, 1)
        XCTAssertEqual(income.categories.map(\.categoryName), ["工资"])
    }

    func testCategoryAggregationProvidesExactShareUnknownFallbackAndStableSort() throws {
        let firstID = uuid(11)
        let secondID = uuid(12)
        let unknownID = uuid(13)
        let categories = [
            LedgerCategory(id: secondID, name: "同名", kind: .expense),
            LedgerCategory(id: firstID, name: "同名", kind: .expense),
            LedgerCategory(id: unknownID, name: "错误方向", kind: .income),
        ]
        let entries = try [
            entry(1, kind: .expense, categoryID: secondID, amount: 100, date: date(2026, 1, 2)),
            entry(2, kind: .expense, categoryID: firstID, amount: 60, date: date(2026, 1, 3)),
            entry(3, kind: .expense, categoryID: firstID, amount: 40, date: date(2026, 1, 4)),
            entry(4, kind: .expense, categoryID: unknownID, amount: 50, date: date(2026, 1, 5)),
        ]
        let result = try LedgerStatisticsCalculator.snapshot(
            entries: entries,
            categories: categories,
            kind: .expense,
            dateRange: try monthRange(2026, 1)
        )

        XCTAssertEqual(result.totalMinorUnits, 250)
        XCTAssertEqual(result.categories.map(\.categoryID), [firstID, secondID, unknownID])
        XCTAssertEqual(result.categories[0].entryCount, 2)
        XCTAssertEqual(result.categories[0].entryIDs, [uuid(2), uuid(3)])
        XCTAssertEqual(result.categories[0].share, LedgerStatisticsRatio(
            numeratorMinorUnits: 100,
            denominatorMinorUnits: 250
        ))
        XCTAssertEqual(result.categories[1].share.numeratorMinorUnits, 100)
        XCTAssertEqual(result.categories[1].share.denominatorMinorUnits, 250)
        XCTAssertEqual(result.categories[2].categoryName, LedgerCategoryStatistics.unknownCategoryName)
        XCTAssertFalse(result.categories[2].isKnownCategory)

        let summary = try LedgerSummary(entries: entries, dateRange: try monthRange(2026, 1))
        XCTAssertEqual(result.totalMinorUnits, summary.expenseMinorUnits)
    }

    func testEntryRankingUsesAllStableTieBreakers() throws {
        let categoryID = uuid(20)
        let category = LedgerCategory(id: categoryID, name: "餐饮", kind: .expense)
        let olderDate = date(2026, 1, 3)
        let newerDate = date(2026, 1, 4)
        let earlierCreation = date(2026, 1, 1)
        let laterCreation = date(2026, 1, 2)
        let entries = try [
            entry(4, kind: .expense, categoryID: categoryID, amount: 100, date: olderDate),
            entry(3, kind: .expense, categoryID: categoryID, amount: 100, date: newerDate, createdAt: earlierCreation),
            entry(2, kind: .expense, categoryID: categoryID, amount: 100, date: newerDate, createdAt: laterCreation),
            entry(1, kind: .expense, categoryID: categoryID, amount: 100, date: newerDate, createdAt: laterCreation),
            entry(5, kind: .expense, categoryID: categoryID, amount: 200, date: olderDate),
        ]

        let result = try LedgerStatisticsCalculator.snapshot(
            entries: entries,
            categories: [category],
            kind: .expense,
            dateRange: try monthRange(2026, 1)
        )
        XCTAssertEqual(result.rankedEntries.map(\.id), [uuid(5), uuid(1), uuid(2), uuid(3), uuid(4)])
    }

    func testMonthlyTrendContainsSixMonthsAcrossYearAndKeepsZeros() throws {
        let categoryID = uuid(30)
        let category = LedgerCategory(id: categoryID, name: "交通", kind: .expense)
        let entries = try [
            entry(1, kind: .expense, categoryID: categoryID, amount: 100, date: date(2025, 9, 10)),
            entry(2, kind: .expense, categoryID: categoryID, amount: 200, date: date(2025, 11, 10)),
            entry(3, kind: .expense, categoryID: categoryID, amount: 300, date: date(2026, 2, 10)),
            entry(4, kind: .income, categoryID: uuid(31), amount: 999, date: date(2026, 1, 10)),
        ]
        let result = try LedgerStatisticsCalculator.monthly(
            entries: entries,
            categories: [category],
            kind: .expense,
            monthContaining: date(2026, 2, 15),
            calendar: calendar
        )

        XCTAssertEqual(result.snapshot.totalMinorUnits, 300)
        XCTAssertEqual(result.trend.count, 6)
        XCTAssertEqual(result.trend.map { calendar.component(.year, from: $0.dateRange.start) }, [2025, 2025, 2025, 2025, 2026, 2026])
        XCTAssertEqual(result.trend.map { calendar.component(.month, from: $0.dateRange.start) }, [9, 10, 11, 12, 1, 2])
        XCTAssertEqual(result.trend.map(\.amountMinorUnits), [100, 0, 200, 0, 0, 300])
        XCTAssertEqual(result.trend.map(\.entryCount), [1, 0, 1, 0, 0, 1])
        XCTAssertEqual(result.trend.map(\.entryIDs), [[uuid(1)], [], [uuid(2)], [], [], [uuid(3)]])
    }

    func testEmptySelectedMonthStillReturnsSnapshotAndSixZeroPoints() throws {
        let result = try LedgerStatisticsCalculator.monthly(
            entries: [],
            categories: [],
            kind: .income,
            monthContaining: date(2026, 7, 8),
            calendar: calendar
        )

        XCTAssertEqual(result.snapshot.totalMinorUnits, 0)
        XCTAssertEqual(result.snapshot.entryCount, 0)
        XCTAssertTrue(result.snapshot.categories.isEmpty)
        XCTAssertTrue(result.snapshot.rankedEntries.isEmpty)
        XCTAssertEqual(result.trend.count, 6)
        XCTAssertTrue(result.trend.allSatisfy { $0.amountMinorUnits == 0 && $0.entryCount == 0 })
        XCTAssertTrue(result.trend.allSatisfy(\.entryIDs.isEmpty))
    }

    func testCalendarTimeZoneControlsSelectedMonthAndSixMonthRange() throws {
        let instant = date(2026, 3, 1, hour: 0, minute: 30)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        let shanghaiRange = try LedgerStatisticsCalculator.sixMonthDateRange(
            endingAtMonthContaining: instant,
            calendar: calendar
        )
        let newYorkRange = try LedgerStatisticsCalculator.sixMonthDateRange(
            endingAtMonthContaining: instant,
            calendar: newYork
        )

        XCTAssertEqual(calendar.component(.month, from: shanghaiRange.end.addingTimeInterval(-1)), 3)
        XCTAssertEqual(newYork.component(.month, from: newYorkRange.end.addingTimeInterval(-1)), 2)
        XCTAssertEqual(calendar.component(.month, from: shanghaiRange.start), 10)
        XCTAssertEqual(newYork.component(.month, from: newYorkRange.start), 9)
        XCTAssertNotEqual(shanghaiRange, newYorkRange)
    }

    func testAmountOverflowThrowsForSnapshotAndEarlierTrendMonth() throws {
        let categoryID = uuid(40)
        let category = LedgerCategory(id: categoryID, name: "餐饮", kind: .expense)
        let overflowingEntries = try [
            entry(1, kind: .expense, categoryID: categoryID, amount: .max, date: date(2026, 1, 2)),
            entry(2, kind: .expense, categoryID: categoryID, amount: 1, date: date(2026, 1, 3)),
        ]

        XCTAssertThrowsError(try LedgerStatisticsCalculator.snapshot(
            entries: overflowingEntries,
            categories: [category],
            kind: .expense,
            dateRange: try monthRange(2026, 1)
        )) { error in
            XCTAssertEqual(error as? LedgerError, .summaryOverflow)
        }
        XCTAssertThrowsError(try LedgerStatisticsCalculator.monthly(
            entries: overflowingEntries,
            categories: [category],
            kind: .expense,
            monthContaining: date(2026, 2, 1),
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? LedgerError, .summaryOverflow)
        }
    }

    func testInvalidEntryAndSelectedDatesThrow() throws {
        let categoryID = uuid(50)
        let invalidEntry = try entry(
            1,
            kind: .expense,
            categoryID: categoryID,
            amount: 1,
            date: Date(timeIntervalSinceReferenceDate: .infinity)
        )

        XCTAssertThrowsError(try LedgerStatisticsCalculator.snapshot(
            entries: [invalidEntry],
            categories: [],
            kind: .expense,
            dateRange: try monthRange(2026, 1)
        )) { error in
            XCTAssertEqual(error as? LedgerError, .invalidDate)
        }
        XCTAssertThrowsError(try LedgerStatisticsCalculator.monthly(
            entries: [],
            categories: [],
            kind: .expense,
            monthContaining: Date(timeIntervalSinceReferenceDate: .nan),
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? LedgerError, .invalidDate)
        }
    }

    private func entry(
        _ id: Int,
        kind: LedgerEntryKind,
        categoryID: UUID,
        amount: Int64,
        date: Date,
        createdAt: Date? = nil
    ) throws -> LedgerEntry {
        let draft = LedgerEntryDraft(
            bookID: bookID,
            categoryID: categoryID,
            kind: kind,
            amount: try LedgerAmount(minorUnits: amount),
            date: date
        )
        return LedgerEntry(
            id: uuid(id),
            draft: draft,
            createdAt: createdAt ?? date,
            updatedAt: createdAt ?? date
        )
    }

    private func category(
        _ id: Int,
        name: String,
        kind: LedgerEntryKind
    ) -> LedgerCategory {
        LedgerCategory(id: uuid(id), name: name, kind: kind)
    }

    private func monthRange(_ year: Int, _ month: Int) throws -> LedgerDateRange {
        try LedgerDateRanges.range(
            for: .month,
            containing: date(year, month, 15),
            calendar: calendar
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
