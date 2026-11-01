import Foundation
import XCTest
import YoloLedgerCore

final class LedgerScheduledEntryRepositoryTests: XCTestCase {
    func testExistentialSupportsRuleLifecycleAtomicProcessingAndNextDate() async throws {
        let ruleID = UUID(uuidString: "287EAA7C-5897-4707-A7D7-3D4593110344")!
        let month = try LedgerYearMonth(year: 2026, month: 11)
        let timestamp = Date(timeIntervalSince1970: 1_793_500_000)
        let rule = try LedgerScheduledEntryRule(
            id: ruleID,
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: LedgerSeedData.categories[0].id,
            kind: .expense,
            amount: LedgerAmount(input: "8.88"),
            note: "协议桩",
            monthlyDay: .fixed(8),
            isEnabled: true,
            effectiveStartMonth: month,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let occurrence = LedgerScheduledOccurrenceMetadata(ruleID: ruleID, month: month)
        let draft = LedgerEntryDraft(
            bookID: rule.bookID,
            categoryID: rule.categoryID,
            kind: rule.kind,
            amount: rule.amount,
            date: timestamp,
            note: rule.note,
            source: .scheduled,
            scheduledOccurrence: occurrence
        )
        let entry = LedgerEntry(id: UUID(), draft: draft, createdAt: timestamp, updatedAt: timestamp)
        let nextDate = Date(timeIntervalSince1970: 1_796_000_000)
        let stub = ScheduledEntryRepositoryStub(rule: rule, entry: entry, nextDate: nextDate)
        let repository: any LedgerScheduledEntryRepository = stub
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let fetched = try await repository.fetchScheduledEntryRules()
        let saved = try await repository.saveScheduledEntryRuleVersion(rule)
        let paused = try await repository.pauseScheduledEntryRule(
            id: ruleID,
            effectiveMonth: month,
            updatedAt: timestamp
        )
        let resumed = try await repository.resumeScheduledEntryRule(
            id: ruleID,
            effectiveStartMonth: month,
            updatedAt: timestamp
        )
        XCTAssertEqual(fetched, [rule])
        XCTAssertEqual(saved, rule)
        XCTAssertEqual(paused, rule)
        XCTAssertEqual(resumed, rule)
        let processing = try await repository.processDueScheduledEntries(
            now: timestamp,
            calendar: calendar,
            timeZone: timeZone
        )
        XCTAssertEqual(processing.generatedEntries, [entry])
        XCTAssertEqual(processing.generatedCount, 1)
        XCTAssertEqual(processing.skippedOccurrenceCount, 2)
        let reportedNextDate = try await repository.nextScheduledEntryDate(
            after: timestamp,
            calendar: calendar,
            timeZone: timeZone
        )
        XCTAssertEqual(reportedNextDate, nextDate)
        try await repository.deleteScheduledEntryRule(id: ruleID, deletedAt: timestamp)

        let calls = await stub.recordedCalls()
        XCTAssertEqual(calls.savedRuleID, ruleID)
        XCTAssertEqual(calls.pauseMonth, month)
        XCTAssertEqual(calls.resumeMonth, month)
        XCTAssertEqual(calls.deletedRuleID, ruleID)
        XCTAssertTrue(calls.processed)
        XCTAssertTrue(calls.requestedNextDate)
    }

    func testRepositoryErrorsRemainSpecificValueObjects() throws {
        let id = UUID()
        let month = try LedgerYearMonth(year: 2026, month: 12)
        XCTAssertNotNil(LedgerScheduledEntryRepositoryError.ruleNotFound(id).errorDescription)
        XCTAssertNotNil(LedgerScheduledEntryRepositoryError.ruleVersionAlreadyExists(
            ruleID: id,
            effectiveStartMonth: month
        ).errorDescription)
    }
}

private actor ScheduledEntryRepositoryStub: LedgerScheduledEntryRepository {
    struct Calls: Sendable {
        var savedRuleID: UUID?
        var pauseMonth: LedgerYearMonth?
        var resumeMonth: LedgerYearMonth?
        var deletedRuleID: UUID?
        var processed = false
        var requestedNextDate = false
    }

    private let rule: LedgerScheduledEntryRule
    private let entry: LedgerEntry
    private let nextDate: Date
    private var calls = Calls()

    init(rule: LedgerScheduledEntryRule, entry: LedgerEntry, nextDate: Date) {
        self.rule = rule
        self.entry = entry
        self.nextDate = nextDate
    }

    func fetchScheduledEntryRules() async throws -> [LedgerScheduledEntryRule] {
        [rule]
    }

    func saveScheduledEntryRuleVersion(
        _ rule: LedgerScheduledEntryRule
    ) async throws -> LedgerScheduledEntryRule {
        calls.savedRuleID = rule.id
        return rule
    }

    func pauseScheduledEntryRule(
        id: UUID,
        effectiveMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule {
        calls.pauseMonth = effectiveMonth
        return rule
    }

    func resumeScheduledEntryRule(
        id: UUID,
        effectiveStartMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule {
        calls.resumeMonth = effectiveStartMonth
        return rule
    }

    func deleteScheduledEntryRule(id: UUID, deletedAt: Date) async throws {
        calls.deletedRuleID = id
    }

    func processDueScheduledEntries(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> LedgerScheduledProcessingResult {
        calls.processed = true
        return LedgerScheduledProcessingResult(
            generatedEntries: [entry],
            skippedOccurrenceCount: 2
        )
    }

    func nextScheduledEntryDate(
        after now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> Date? {
        calls.requestedNextDate = true
        return nextDate
    }

    func recordedCalls() -> Calls { calls }
}
