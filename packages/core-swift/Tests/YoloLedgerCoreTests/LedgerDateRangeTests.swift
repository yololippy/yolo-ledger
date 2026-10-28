import Foundation
import XCTest
import YoloLedgerCore

final class LedgerDateRangeTests: XCTestCase {
    private func calendar(_ zone: String, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testLocalDayUsesItsTimeZoneAndExcludesNextMidnight() throws {
        let calendar = calendar("Asia/Shanghai")
        let day = try LedgerDateRanges.range(for: .day, containing: date(2026, 10, 28, hour: 15, in: calendar), calendar: calendar)
        XCTAssertEqual(day.start, date(2026, 10, 28, in: calendar))
        XCTAssertEqual(day.end, date(2026, 10, 29, in: calendar))
        XCTAssertTrue(day.contains(day.start))
        XCTAssertTrue(day.contains(day.end.addingTimeInterval(-0.001)))
        XCTAssertFalse(day.contains(day.end))
        XCTAssertFalse(day.contains(day.start.addingTimeInterval(-0.001)))
    }

    func testMonthAndYearCrossDecemberAndLeapFebruary() throws {
        let calendar = calendar("Asia/Shanghai")
        let december = try LedgerDateRanges.range(for: .month, containing: date(2026, 12, 31, hour: 23, in: calendar), calendar: calendar)
        XCTAssertEqual(december.start, date(2026, 12, 1, in: calendar))
        XCTAssertEqual(december.end, date(2027, 1, 1, in: calendar))

        let february = try LedgerDateRanges.range(for: .month, containing: date(2024, 2, 29, hour: 12, in: calendar), calendar: calendar)
        XCTAssertEqual(february.start, date(2024, 2, 1, in: calendar))
        XCTAssertEqual(february.end, date(2024, 3, 1, in: calendar))
        XCTAssertEqual(february.end.timeIntervalSince(february.start), 29 * 86400)

        let year = try LedgerDateRanges.range(for: .year, containing: date(2024, 12, 31, hour: 23, in: calendar), calendar: calendar)
        XCTAssertEqual(year.start, date(2024, 1, 1, in: calendar))
        XCTAssertEqual(year.end, date(2025, 1, 1, in: calendar))
        XCTAssertEqual(year.end.timeIntervalSince(year.start), 366 * 86400)
    }

    func testWeekRespectsCalendarFirstWeekday() throws {
        let mondayFirst = calendar("Asia/Shanghai", firstWeekday: 2)
        let sundayFirst = calendar("Asia/Shanghai", firstWeekday: 1)
        let sunday = date(2026, 10, 25, hour: 12, in: mondayFirst)
        let mondayWeek = try LedgerDateRanges.range(for: .week, containing: sunday, calendar: mondayFirst)
        let sundayWeek = try LedgerDateRanges.range(for: .week, containing: sunday, calendar: sundayFirst)
        XCTAssertEqual(mondayWeek.start, date(2026, 10, 19, in: mondayFirst))
        XCTAssertEqual(mondayWeek.end, date(2026, 10, 26, in: mondayFirst))
        XCTAssertEqual(sundayWeek.start, date(2026, 10, 25, in: sundayFirst))
        XCTAssertEqual(sundayWeek.end, date(2026, 11, 1, in: sundayFirst))
    }

    func testDaylightSavingDaysCanHave23Or25Hours() throws {
        let calendar = calendar("America/New_York")
        let spring = try LedgerDateRanges.range(for: .day, containing: date(2026, 3, 8, hour: 12, in: calendar), calendar: calendar)
        let fall = try LedgerDateRanges.range(for: .day, containing: date(2026, 11, 1, hour: 12, in: calendar), calendar: calendar)
        XCTAssertEqual(spring.start, date(2026, 3, 8, in: calendar))
        XCTAssertEqual(spring.end, date(2026, 3, 9, in: calendar))
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        XCTAssertEqual(fall.start, date(2026, 11, 1, in: calendar))
        XCTAssertEqual(fall.end, date(2026, 11, 2, in: calendar))
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 25 * 3600)
    }

    func testWeekAndMonthAcrossDSTKeepLocalMidnightBoundaries() throws {
        let calendar = calendar("America/New_York")
        let date = date(2026, 3, 8, hour: 12, in: calendar)
        let week = try LedgerDateRanges.range(for: .week, containing: date, calendar: calendar)
        let month = try LedgerDateRanges.range(for: .month, containing: date, calendar: calendar)
        XCTAssertEqual(week.end.timeIntervalSince(week.start), 7 * 86400 - 3600)
        XCTAssertEqual(month.end.timeIntervalSince(month.start), 31 * 86400 - 3600)
        XCTAssertEqual(calendar.component(.hour, from: week.end), 0)
        XCTAssertEqual(calendar.component(.hour, from: month.end), 0)
    }

    func testChangingLocalTimeZoneChangesThePeriodForTheSameInstant() throws {
        let shanghai = calendar("Asia/Shanghai")
        let newYork = calendar("America/New_York")
        let instant = date(2026, 1, 1, hour: 1, in: shanghai)
        let shanghaiYear = try LedgerDateRanges.range(for: .year, containing: instant, calendar: shanghai)
        let newYorkYear = try LedgerDateRanges.range(for: .year, containing: instant, calendar: newYork)
        XCTAssertEqual(shanghai.component(.year, from: shanghaiYear.start), 2026)
        XCTAssertEqual(newYork.component(.year, from: newYorkYear.start), 2025)
        XCTAssertTrue(shanghaiYear.contains(instant))
        XCTAssertTrue(newYorkYear.contains(instant))
    }

    func testDefaultCalendarUsesCurrentLocalSettings() throws {
        let date = Date(timeIntervalSince1970: 1_798_000_000)
        XCTAssertEqual(
            try LedgerDateRanges.range(for: .month, containing: date),
            try LedgerDateRanges.range(for: .month, containing: date, calendar: .current)
        )
    }

    func testInvalidIntervalsAndDatesThrow() {
        let date = Date()
        for end in [date, date.addingTimeInterval(-1), Date(timeIntervalSinceReferenceDate: .infinity)] {
            XCTAssertThrowsError(try LedgerDateRange(start: date, end: end)) { error in
                XCTAssertEqual(error as? LedgerError, .invalidDateRange)
            }
        }
        XCTAssertThrowsError(try LedgerDateRanges.range(for: .day, containing: Date(timeIntervalSinceReferenceDate: .nan))) { error in
            XCTAssertEqual(error as? LedgerError, .invalidDate)
        }
    }
}
