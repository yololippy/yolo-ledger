import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct LedgerScheduledEntryControllerTests {
    @Test
    func editorMovesPastRuleMonthForwardToCurrentMonth() throws {
        let past = try LedgerYearMonth(year: 2025, month: 12)
        let current = try LedgerYearMonth(year: 2026, month: 11)

        #expect(LedgerScheduledEntryMonthPolicy.clampedToCurrentMonth(
            ruleMonth: past,
            currentMonth: current
        ) == current)
    }

    @Test
    func editorKeepsFutureRuleMonth() throws {
        let current = try LedgerYearMonth(year: 2026, month: 11)
        let future = try LedgerYearMonth(year: 2027, month: 2)

        #expect(LedgerScheduledEntryMonthPolicy.clampedToCurrentMonth(
            ruleMonth: future,
            currentMonth: current
        ) == future)
    }

    @Test
    func generatedEntryActionOnlyRunsForPositiveCounts() {
        var callCount = 0

        LedgerScheduledEntryController.performGeneratedEntriesAction(generatedCount: 0) {
            callCount += 1
        }
        #expect(callCount == 0)

        LedgerScheduledEntryController.performGeneratedEntriesAction(generatedCount: 2) {
            callCount += 1
        }
        #expect(callCount == 1)
    }

    @Test
    func loadCanRetryAndUsesStableCreationOrder() async throws {
        let paused = try rule(
            enabled: false,
            month: LedgerYearMonth(year: 2026, month: 12),
            createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let enabled = try rule(
            enabled: true,
            month: LedgerYearMonth(year: 2026, month: 11),
            createdAt: Date(timeIntervalSince1970: 1_760_000_060)
        )
        let repository = ScheduledRepositoryStub(rules: [paused, enabled])
        await repository.setReadFailure(true)
        let controller = LedgerScheduledEntryController(repository: repository)

        await controller.load()
        #expect(controller.rules.isEmpty)
        #expect(controller.loadError != nil)

        await repository.setReadFailure(false)
        await controller.load()
        #expect(controller.rules.map(\.id) == [paused.id, enabled.id])
        #expect(controller.loadError == nil)
    }

    @Test
    func pausingRuleKeepsItsPosition() async throws {
        let month = try LedgerYearMonth(year: 2026, month: 11)
        let first = try rule(
            enabled: true,
            month: month,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let second = try rule(
            enabled: true,
            month: month,
            createdAt: Date(timeIntervalSince1970: 1_760_000_060)
        )
        let repository = ScheduledRepositoryStub(rules: [second, first])
        let controller = LedgerScheduledEntryController(repository: repository)
        await controller.load()
        let originalOrder = controller.rules.map(\.id)

        #expect(await controller.setEnabled(false, for: first))
        #expect(controller.rules.map(\.id) == originalOrder)
        #expect(controller.rules.first?.isEnabled == false)
    }

    @Test
    func savingEnabledRuleTriggersOnlyTheImmediateProcessingHook() async throws {
        let repository = ScheduledRepositoryStub()
        let controller = LedgerScheduledEntryController(repository: repository)
        let recorder = ScheduledActionRecorder()
        controller.installActions(
            enabledRuleSaved: { recorder.enabledSaveCount += 1 },
            rulesChanged: { recorder.rulesChangedCount += 1 }
        )
        let content = try rule(enabled: true, month: LedgerYearMonth(year: 2026, month: 11))

        #expect(await controller.save(content))
        #expect(controller.rules == [content])
        #expect(recorder.enabledSaveCount == 1)
        #expect(recorder.rulesChangedCount == 0)
        #expect(await repository.savedCount == 1)
    }

    @Test
    func savingPausedRuleOnlyReschedulesWithoutImmediateProcessing() async throws {
        let repository = ScheduledRepositoryStub()
        let controller = LedgerScheduledEntryController(repository: repository)
        let recorder = ScheduledActionRecorder()
        controller.installActions(
            enabledRuleSaved: { recorder.enabledSaveCount += 1 },
            rulesChanged: { recorder.rulesChangedCount += 1 }
        )
        let content = try rule(enabled: false, month: LedgerYearMonth(year: 2026, month: 11))

        #expect(await controller.save(content))
        #expect(controller.rules == [content])
        #expect(recorder.enabledSaveCount == 0)
        #expect(recorder.rulesChangedCount == 1)
    }

    @Test
    func pauseResumeAndDeleteUseCurrentLocalMonth() async throws {
        let initial = try rule(enabled: true, month: LedgerYearMonth(year: 2026, month: 10))
        let repository = ScheduledRepositoryStub(rules: [initial])
        let controller = LedgerScheduledEntryController(repository: repository)
        let recorder = ScheduledActionRecorder()
        controller.installActions(
            enabledRuleSaved: { recorder.enabledSaveCount += 1 },
            rulesChanged: { recorder.rulesChangedCount += 1 }
        )
        await controller.load()
        var calendar = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        calendar.timeZone = zone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))

        #expect(await controller.setEnabled(false, for: initial, now: now, calendar: calendar, timeZone: zone))
        let paused = try #require(controller.rules.first)
        let november = try LedgerYearMonth(year: 2026, month: 11)
        #expect(!paused.isEnabled)
        #expect(paused.effectiveStartMonth == november)

        #expect(await controller.setEnabled(true, for: paused, now: now, calendar: calendar, timeZone: zone))
        let resumed = try #require(controller.rules.first)
        #expect(resumed.isEnabled)
        #expect(recorder.enabledSaveCount == 1)

        #expect(await controller.delete(resumed, now: now))
        #expect(controller.rules.isEmpty)
        #expect(recorder.rulesChangedCount == 2)
    }

    @Test
    func pauseAndResumeFutureRuleUseItsFutureStartMonth() async throws {
        let futureMonth = try LedgerYearMonth(year: 2027, month: 2)
        let initial = try rule(enabled: true, month: futureMonth)
        let repository = ScheduledRepositoryStub(rules: [initial])
        let controller = LedgerScheduledEntryController(repository: repository)
        await controller.load()
        var calendar = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        calendar.timeZone = zone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))

        #expect(await controller.setEnabled(false, for: initial, now: now, calendar: calendar, timeZone: zone))
        let paused = try #require(controller.rules.first)
        #expect(!paused.isEnabled)
        #expect(paused.effectiveStartMonth == futureMonth)

        #expect(await controller.setEnabled(true, for: paused, now: now, calendar: calendar, timeZone: zone))
        let resumed = try #require(controller.rules.first)
        #expect(resumed.isEnabled)
        #expect(resumed.effectiveStartMonth == futureMonth)
    }

    @Test
    func writeFailureKeepsExistingRuleAndReportsSafeMessage() async throws {
        let initial = try rule(enabled: true, month: LedgerYearMonth(year: 2026, month: 11))
        let repository = ScheduledRepositoryStub(rules: [initial])
        let controller = LedgerScheduledEntryController(repository: repository)
        await controller.load()
        await repository.setWriteFailure(true)
        let replacement = try LedgerScheduledEntryRule(
            id: initial.id,
            bookID: initial.bookID,
            categoryID: initial.categoryID,
            kind: .income,
            amount: LedgerAmount(input: "99.00"),
            note: "修改",
            monthlyDay: .lastDay,
            isEnabled: true,
            effectiveStartMonth: LedgerYearMonth(year: 2026, month: 12),
            createdAt: initial.createdAt,
            updatedAt: initial.updatedAt.addingTimeInterval(60)
        )

        #expect(!(await controller.save(replacement)))
        #expect(controller.rules == [initial])
        #expect(controller.operationError == "测试写入失败。")
        #expect(!controller.isSaving)
    }

    @Test
    func processingRevisionRefreshesRulesAndPublishesGeneratedCount() async throws {
        let repository = ScheduledRepositoryStub()
        let controller = LedgerScheduledEntryController(repository: repository)
        let content = try rule(enabled: true, month: LedgerYearMonth(year: 2026, month: 11))
        await repository.replaceRules([content])

        await controller.reportSuccessfulProcessing(generatedCount: 2)

        #expect(controller.successfulProcessingRevision == 1)
        #expect(controller.lastGeneratedCount == 2)
        #expect(controller.rules == [content])
    }

    private func rule(
        enabled: Bool,
        month: LedgerYearMonth,
        createdAt: Date = Date(timeIntervalSince1970: 1_760_000_000)
    ) throws -> LedgerScheduledEntryRule {
        return try LedgerScheduledEntryRule(
            id: UUID(),
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: LedgerSeedData.categories[0].id,
            kind: .expense,
            amount: LedgerAmount(input: "12.34"),
            note: "月度测试",
            monthlyDay: .fixed(8),
            isEnabled: enabled,
            effectiveStartMonth: month,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

@MainActor
private final class ScheduledActionRecorder {
    var enabledSaveCount = 0
    var rulesChangedCount = 0
}

private actor ScheduledRepositoryStub: LedgerScheduledEntryRepository {
    private var rules: [UUID: LedgerScheduledEntryRule]
    private var readFailure = false
    private var writeFailure = false
    private(set) var savedCount = 0

    init(rules: [LedgerScheduledEntryRule] = []) {
        self.rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    }

    func setReadFailure(_ value: Bool) { readFailure = value }
    func setWriteFailure(_ value: Bool) { writeFailure = value }
    func replaceRules(_ values: [LedgerScheduledEntryRule]) {
        rules = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    func fetchScheduledEntryRules() async throws -> [LedgerScheduledEntryRule] {
        if readFailure { throw ScheduledTestError.read }
        return Array(rules.values)
    }

    func saveScheduledEntryRuleVersion(_ rule: LedgerScheduledEntryRule) async throws -> LedgerScheduledEntryRule {
        try checkWrite()
        savedCount += 1
        rules[rule.id] = rule
        return rule
    }

    func pauseScheduledEntryRule(
        id: UUID,
        effectiveMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule {
        try checkWrite()
        guard let rule = rules[id] else { throw LedgerScheduledEntryRepositoryError.ruleNotFound(id) }
        let result = try copy(rule, enabled: false, month: effectiveMonth, updatedAt: updatedAt)
        rules[id] = result
        return result
    }

    func resumeScheduledEntryRule(
        id: UUID,
        effectiveStartMonth: LedgerYearMonth,
        updatedAt: Date
    ) async throws -> LedgerScheduledEntryRule {
        try checkWrite()
        guard let rule = rules[id] else { throw LedgerScheduledEntryRepositoryError.ruleNotFound(id) }
        let result = try copy(rule, enabled: true, month: effectiveStartMonth, updatedAt: updatedAt)
        rules[id] = result
        return result
    }

    func deleteScheduledEntryRule(id: UUID, deletedAt: Date) async throws {
        try checkWrite()
        guard rules.removeValue(forKey: id) != nil else {
            throw LedgerScheduledEntryRepositoryError.ruleNotFound(id)
        }
    }

    func processDueScheduledEntries(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> LedgerScheduledProcessingResult {
        LedgerScheduledProcessingResult(generatedEntries: [], skippedOccurrenceCount: 0)
    }

    func nextScheduledEntryDate(
        after now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) async throws -> Date? {
        nil
    }

    private func checkWrite() throws {
        if writeFailure { throw ScheduledTestError.write }
    }

    private func copy(
        _ rule: LedgerScheduledEntryRule,
        enabled: Bool,
        month: LedgerYearMonth,
        updatedAt: Date
    ) throws -> LedgerScheduledEntryRule {
        try LedgerScheduledEntryRule(
            id: rule.id,
            bookID: rule.bookID,
            categoryID: rule.categoryID,
            kind: rule.kind,
            amount: rule.amount,
            note: rule.note,
            monthlyDay: rule.monthlyDay,
            isEnabled: enabled,
            effectiveStartMonth: month,
            createdAt: rule.createdAt,
            updatedAt: updatedAt
        )
    }
}

private enum ScheduledTestError: LocalizedError {
    case read, write

    var errorDescription: String? {
        switch self {
        case .read: "测试读取失败。"
        case .write: "测试写入失败。"
        }
    }
}
