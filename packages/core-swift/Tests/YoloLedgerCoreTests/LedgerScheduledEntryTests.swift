import Foundation
import XCTest
import YoloLedgerCore

final class LedgerScheduledEntryTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private let ruleID = UUID(uuidString: "D85F3058-332D-4E40-A9D8-C010D4DA23DF")!

    func testFixedDayClampsToMonthEndAndLastDayHandlesLeapYear() throws {
        let nonLeap = try LedgerScheduledEntryPlanner.scheduledDate(
            for: .fixed(31),
            in: LedgerYearMonth(year: 2026, month: 2),
            calendar: calendar(),
            timeZone: shanghai
        )
        let leap = try LedgerScheduledEntryPlanner.scheduledDate(
            for: .fixed(31),
            in: LedgerYearMonth(year: 2028, month: 2),
            calendar: calendar(),
            timeZone: shanghai
        )
        let aprilLastDay = try LedgerScheduledEntryPlanner.scheduledDate(
            for: .lastDay,
            in: LedgerYearMonth(year: 2026, month: 4),
            calendar: calendar(),
            timeZone: shanghai
        )

        assertLocal(nonLeap, year: 2026, month: 2, day: 28, timeZone: shanghai)
        assertLocal(leap, year: 2028, month: 2, day: 29, timeZone: shanghai)
        assertLocal(aprilLastDay, year: 2026, month: 4, day: 30, timeZone: shanghai)
    }

    func testInjectedTimeZoneChangesTheAbsoluteScheduledInstant() throws {
        let month = try LedgerYearMonth(year: 2026, month: 11)
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let shanghaiDate = try LedgerScheduledEntryPlanner.scheduledDate(
            for: .fixed(1),
            in: month,
            calendar: calendar(),
            timeZone: shanghai
        )
        let utcDate = try LedgerScheduledEntryPlanner.scheduledDate(
            for: .fixed(1),
            in: month,
            calendar: calendar(),
            timeZone: utc
        )

        XCTAssertEqual(utcDate.timeIntervalSince(shanghaiDate), 8 * 60 * 60)
        assertLocal(shanghaiDate, year: 2026, month: 11, day: 1, timeZone: shanghai)
        assertLocal(utcDate, year: 2026, month: 11, day: 1, timeZone: utc)
    }

    func testCrossMonthCatchUpSkipsHandledGeneratedOrDeletedOccurrence() throws {
        let rule = try makeRule(
            monthlyDay: .fixed(31),
            start: LedgerYearMonth(year: 2026, month: 1)
        )
        let handledFebruary = LedgerScheduledOccurrenceIdentity.key(
            ruleID: rule.id,
            month: try LedgerYearMonth(year: 2026, month: 2)
        )
        let now = date(2026, 4, 15, hour: 12, timeZone: shanghai)

        let occurrences = try LedgerScheduledEntryPlanner.dueOccurrences(
            for: rule,
            through: now,
            excluding: [handledFebruary],
            calendar: calendar(),
            timeZone: shanghai
        )

        XCTAssertEqual(occurrences.map(\.month.key), ["2026-01", "2026-03"])
        XCTAssertEqual(occurrences.map(\.scheduledDate).map {
            calendar(timeZone: shanghai).component(.day, from: $0)
        }, [31, 31])
        XCTAssertTrue(occurrences.allSatisfy { $0.draft.source == .scheduled })
        XCTAssertTrue(occurrences.allSatisfy {
            $0.draft.scheduledOccurrence?.occurrenceKey == $0.occurrenceKey
        })
        XCTAssertTrue(occurrences.allSatisfy { $0.draft.importMetadata == nil })
        let first = try XCTUnwrap(occurrences.first)
        let persistedEntry = LedgerEntry(
            id: UUID(),
            draft: first.draft,
            createdAt: now,
            updatedAt: now
        )
        XCTAssertEqual(persistedEntry.scheduledOccurrence, first.metadata)
        XCTAssertEqual(persistedEntry.draft.scheduledOccurrence, first.metadata)
    }

    func testPausedRuleDoesNotCatchUpAndResumeStartsAtResumeMonth() throws {
        let paused = try makeRule(
            monthlyDay: .fixed(10),
            isEnabled: false,
            start: LedgerYearMonth(year: 2026, month: 1)
        )
        let now = date(2026, 5, 20, hour: 12, timeZone: shanghai)
        XCTAssertEqual(try LedgerScheduledEntryPlanner.dueOccurrences(
            for: paused,
            through: now,
            calendar: calendar(),
            timeZone: shanghai
        ), [])
        XCTAssertNil(try LedgerScheduledEntryPlanner.nextExecutionDate(
            for: paused,
            after: now,
            calendar: calendar(),
            timeZone: shanghai
        ))

        let resumed = try makeRule(
            monthlyDay: .fixed(10),
            isEnabled: true,
            start: LedgerYearMonth(year: 2026, month: 4)
        )
        let resumedOccurrences = try LedgerScheduledEntryPlanner.dueOccurrences(
            for: resumed,
            through: now,
            calendar: calendar(),
            timeZone: shanghai
        )
        XCTAssertEqual(resumedOccurrences.map(\.month.key), ["2026-04", "2026-05"])
    }

    func testNextExecutionUsesCurrentOrFollowingMonthAtLocalDayBoundary() throws {
        let rule = try makeRule(
            monthlyDay: .fixed(20),
            start: LedgerYearMonth(year: 2026, month: 11)
        )
        let before = date(2026, 11, 19, hour: 23, timeZone: shanghai)
        let after = date(2026, 11, 20, hour: 1, timeZone: shanghai)
        let current = try XCTUnwrap(LedgerScheduledEntryPlanner.nextExecutionDate(
            for: rule,
            after: before,
            calendar: calendar(),
            timeZone: shanghai
        ))
        let following = try XCTUnwrap(LedgerScheduledEntryPlanner.nextExecutionDate(
            for: rule,
            after: after,
            calendar: calendar(),
            timeZone: shanghai
        ))

        assertLocal(current, year: 2026, month: 11, day: 20, timeZone: shanghai)
        assertLocal(following, year: 2026, month: 12, day: 20, timeZone: shanghai)
    }

    func testFutureEffectiveModificationDoesNotRewriteEarlierMonths() throws {
        let modified = try makeRule(
            amount: "99.00",
            monthlyDay: .fixed(5),
            start: LedgerYearMonth(year: 2026, month: 6)
        )
        let mayNow = date(2026, 5, 31, hour: 23, timeZone: shanghai)
        let julyNow = date(2026, 7, 10, hour: 12, timeZone: shanghai)

        XCTAssertEqual(try LedgerScheduledEntryPlanner.dueOccurrences(
            for: modified,
            through: mayNow,
            calendar: calendar(),
            timeZone: shanghai
        ), [])
        let next = try XCTUnwrap(LedgerScheduledEntryPlanner.nextExecutionDate(
            for: modified,
            after: mayNow,
            calendar: calendar(),
            timeZone: shanghai
        ))
        assertLocal(next, year: 2026, month: 6, day: 5, timeZone: shanghai)

        let future = try LedgerScheduledEntryPlanner.dueOccurrences(
            for: modified,
            through: julyNow,
            calendar: calendar(),
            timeZone: shanghai
        )
        XCTAssertEqual(future.map(\.month.key), ["2026-06", "2026-07"])
        XCTAssertEqual(future.map(\.draft.amount.minorUnits), [9_900, 9_900])
    }

    func testOccurrenceKeyIsStableRuleIDPlusYearMonth() throws {
        let month = try LedgerYearMonth(year: 2026, month: 3)
        let metadata = LedgerScheduledOccurrenceMetadata(ruleID: ruleID, month: month)

        XCTAssertEqual(month.key, "2026-03")
        XCTAssertEqual(
            metadata.occurrenceKey,
            "d85f3058-332d-4e40-a9d8-c010d4da23df:2026-03"
        )
        XCTAssertEqual(
            LedgerScheduledOccurrenceIdentity.key(ruleID: ruleID, month: month),
            metadata.occurrenceKey
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                LedgerScheduledOccurrenceMetadata.self,
                from: JSONEncoder().encode(metadata)
            ),
            metadata
        )
    }

    func testInvalidRuleValuesAndDatesAreRejected() throws {
        for day in [0, 32] {
            XCTAssertThrowsError(try makeRule(monthlyDay: .fixed(day))) { error in
                XCTAssertEqual(error as? LedgerScheduledEntryError, .invalidMonthlyDay(day))
            }
        }
        XCTAssertThrowsError(try LedgerYearMonth(year: 2026, month: 13)) { error in
            XCTAssertEqual(
                error as? LedgerScheduledEntryError,
                .invalidYearMonth(year: 2026, month: 13)
            )
        }
        XCTAssertThrowsError(try makeRule(
            monthlyDay: .lastDay,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 9)
        )) { error in
            XCTAssertEqual(error as? LedgerScheduledEntryError, .invalidTimestampOrder)
        }
        let valid = try makeRule(monthlyDay: .lastDay)
        XCTAssertThrowsError(try LedgerScheduledEntryPlanner.dueOccurrences(
            for: valid,
            through: Date(timeIntervalSinceReferenceDate: .infinity),
            calendar: calendar(),
            timeZone: shanghai
        )) { error in
            XCTAssertEqual(error as? LedgerScheduledEntryError, .invalidDate)
        }
    }

    private func makeRule(
        amount: String = "12.34",
        monthlyDay: LedgerMonthlyDay,
        isEnabled: Bool = true,
        start: LedgerYearMonth? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> LedgerScheduledEntryRule {
        try LedgerScheduledEntryRule(
            id: ruleID,
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: LedgerSeedData.categories[0].id,
            kind: .expense,
            amount: LedgerAmount(input: amount),
            note: "固定测试",
            monthlyDay: monthlyDay,
            isEnabled: isEnabled,
            effectiveStartMonth: start ?? LedgerYearMonth(year: 2026, month: 1),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func calendar(timeZone: TimeZone? = nil) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone ?? shanghai
        return value
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        timeZone: TimeZone
    ) -> Date {
        let value = calendar(timeZone: timeZone).date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))
        return value!
    }

    private func assertLocal(
        _ date: Date,
        year: Int,
        month: Int,
        day: Int,
        timeZone: TimeZone,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = calendar(timeZone: timeZone).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        XCTAssertEqual(components.hour, 0, file: file, line: line)
        XCTAssertEqual(components.minute, 0, file: file, line: line)
        XCTAssertEqual(components.second, 0, file: file, line: line)
    }
}
