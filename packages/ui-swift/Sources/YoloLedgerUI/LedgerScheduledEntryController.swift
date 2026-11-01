import Foundation
import Observation
import YoloLedgerCore

enum LedgerScheduledEntryMonthPolicy {
    static func clampedToCurrentMonth(
        ruleMonth: LedgerYearMonth?,
        currentMonth: LedgerYearMonth
    ) -> LedgerYearMonth {
        guard let ruleMonth else { return currentMonth }
        return max(ruleMonth, currentMonth)
    }
}

@MainActor
@Observable
public final class LedgerScheduledEntryController {
    public typealias EnabledRuleSavedAction = @MainActor @Sendable () async -> Void
    public typealias RulesChangedAction = @MainActor @Sendable () async -> Void

    public private(set) var rules: [LedgerScheduledEntryRule] = []
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var loadError: String?
    public private(set) var operationError: String?
    public private(set) var successfulProcessingRevision = 0
    public private(set) var lastGeneratedCount = 0
    public var isListPresented = false

    private let repository: any LedgerScheduledEntryRepository
    private var enabledRuleSavedAction: EnabledRuleSavedAction = {}
    private var rulesChangedAction: RulesChangedAction = {}

    public init(repository: any LedgerScheduledEntryRepository) {
        self.repository = repository
    }

    public static func performGeneratedEntriesAction(
        generatedCount: Int,
        action: () -> Void
    ) {
        guard generatedCount > 0 else { return }
        action()
    }

    public func installActions(
        enabledRuleSaved: @escaping EnabledRuleSavedAction,
        rulesChanged: @escaping RulesChangedAction
    ) {
        enabledRuleSavedAction = enabledRuleSaved
        rulesChangedAction = rulesChanged
    }

    public func presentList() {
        operationError = nil
        isListPresented = true
    }

    public func dismissList() {
        guard !isSaving else { return }
        isListPresented = false
        operationError = nil
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            rules = try await repository.fetchScheduledEntryRules().sorted(by: Self.ruleOrder)
        } catch {
            loadError = Self.message(for: error, fallback: "定时记账规则读取失败，请稍后重试。")
        }
    }

    @discardableResult
    public func save(_ rule: LedgerScheduledEntryRule) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        operationError = nil
        defer { isSaving = false }
        do {
            let saved = try await repository.saveScheduledEntryRuleVersion(rule)
            replace(saved)
            if saved.isEnabled {
                await enabledRuleSavedAction()
            } else {
                await rulesChangedAction()
            }
            return true
        } catch {
            operationError = Self.message(for: error, fallback: "规则保存失败，请稍后重试。")
            return false
        }
    }

    @discardableResult
    public func setEnabled(
        _ enabled: Bool,
        for rule: LedgerScheduledEntryRule,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        operationError = nil
        defer { isSaving = false }
        do {
            let currentMonth = try LedgerYearMonth.containing(now, calendar: calendar, timeZone: timeZone)
            let month = LedgerScheduledEntryMonthPolicy.clampedToCurrentMonth(
                ruleMonth: rule.effectiveStartMonth,
                currentMonth: currentMonth
            )
            let saved: LedgerScheduledEntryRule
            if enabled {
                saved = try await repository.resumeScheduledEntryRule(
                    id: rule.id,
                    effectiveStartMonth: month,
                    updatedAt: now
                )
            } else {
                saved = try await repository.pauseScheduledEntryRule(
                    id: rule.id,
                    effectiveMonth: month,
                    updatedAt: now
                )
            }
            replace(saved)
            if enabled {
                await enabledRuleSavedAction()
            } else {
                await rulesChangedAction()
            }
            return true
        } catch {
            operationError = Self.message(for: error, fallback: "规则状态修改失败，请稍后重试。")
            return false
        }
    }

    @discardableResult
    public func delete(_ rule: LedgerScheduledEntryRule, now: Date = Date()) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        operationError = nil
        defer { isSaving = false }
        do {
            try await repository.deleteScheduledEntryRule(id: rule.id, deletedAt: now)
            rules.removeAll { $0.id == rule.id }
            await rulesChangedAction()
            return true
        } catch {
            operationError = Self.message(for: error, fallback: "规则删除失败，请稍后重试。")
            return false
        }
    }

    public func reportSuccessfulProcessing(generatedCount: Int) async {
        lastGeneratedCount = generatedCount
        successfulProcessingRevision &+= 1
        await load()
    }

    private func replace(_ rule: LedgerScheduledEntryRule) {
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
        rules.sort(by: Self.ruleOrder)
    }

    private static func ruleOrder(_ left: LedgerScheduledEntryRule, _ right: LedgerScheduledEntryRule) -> Bool {
        if left.isEnabled != right.isEnabled { return left.isEnabled && !right.isEnabled }
        if left.effectiveStartMonth != right.effectiveStartMonth {
            return left.effectiveStartMonth < right.effectiveStartMonth
        }
        return left.id.uuidString < right.id.uuidString
    }

    private static func message(for error: any Error, fallback: String) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return fallback
    }
}
