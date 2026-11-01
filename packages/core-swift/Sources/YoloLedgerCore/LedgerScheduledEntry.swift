import Foundation

public enum LedgerScheduledEntryError: Error, Equatable, Sendable, LocalizedError {
    case invalidYearMonth(year: Int, month: Int)
    case invalidMonthlyDay(Int)
    case invalidDate
    case invalidTimestampOrder
    case dateCalculationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidYearMonth:
            "生效月份无效。"
        case .invalidMonthlyDay:
            "每月日期必须在 1 到 31 日之间。"
        case .invalidDate:
            "定时记账日期无效。"
        case .invalidTimestampOrder:
            "更新时间不能早于创建时间。"
        case .dateCalculationFailed:
            "无法按当前日历计算定时记账日期。"
        }
    }
}

/// A calendar year and month used by monthly scheduling and occurrence identity.
public struct LedgerYearMonth: Equatable, Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month) else {
            throw LedgerScheduledEntryError.invalidYearMonth(year: year, month: month)
        }
        self.year = year
        self.month = month
    }

    public var key: String {
        String(format: "%04d-%02d", year, month)
    }

    public static func < (left: Self, right: Self) -> Bool {
        (left.year, left.month) < (right.year, right.month)
    }

    public static func containing(
        _ date: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> Self {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw LedgerScheduledEntryError.invalidDate
        }
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let components = localCalendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            throw LedgerScheduledEntryError.dateCalculationFailed
        }
        return try Self(year: year, month: month)
    }

    public func next() throws -> Self {
        if month < 12 { return try Self(year: year, month: month + 1) }
        guard year < 9999 else {
            throw LedgerScheduledEntryError.invalidYearMonth(year: year + 1, month: 1)
        }
        return try Self(year: year + 1, month: 1)
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            year: container.decode(Int.self, forKey: .year),
            month: container.decode(Int.self, forKey: .month)
        )
    }
}

public enum LedgerMonthlyDay: Equatable, Codable, Sendable {
    case fixed(Int)
    case lastDay
}

/// One effective version of a monthly scheduled-entry rule.
public struct LedgerScheduledEntryRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let categoryID: UUID
    public let kind: LedgerEntryKind
    public let amount: LedgerAmount
    public let note: String
    public let monthlyDay: LedgerMonthlyDay
    public let isEnabled: Bool
    /// Creation, resume, or future-edit month for this effective rule version.
    public let effectiveStartMonth: LedgerYearMonth
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        bookID: UUID,
        categoryID: UUID,
        kind: LedgerEntryKind,
        amount: LedgerAmount,
        note: String = "",
        monthlyDay: LedgerMonthlyDay,
        isEnabled: Bool,
        effectiveStartMonth: LedgerYearMonth,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        if case let .fixed(day) = monthlyDay, !(1...31).contains(day) {
            throw LedgerScheduledEntryError.invalidMonthlyDay(day)
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite
        else { throw LedgerScheduledEntryError.invalidDate }
        guard createdAt <= updatedAt else {
            throw LedgerScheduledEntryError.invalidTimestampOrder
        }
        self.id = id
        self.bookID = bookID
        self.categoryID = categoryID
        self.kind = kind
        self.amount = amount
        self.note = note
        self.monthlyDay = monthlyDay
        self.isEnabled = isEnabled
        self.effectiveStartMonth = effectiveStartMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Identity retained on generated entries, including soft-deleted entries.
public struct LedgerScheduledOccurrenceMetadata: Equatable, Hashable, Codable, Sendable {
    public let ruleID: UUID
    public let month: LedgerYearMonth

    public init(ruleID: UUID, month: LedgerYearMonth) {
        self.ruleID = ruleID
        self.month = month
    }

    public var occurrenceKey: String {
        LedgerScheduledOccurrenceIdentity.key(ruleID: ruleID, month: month)
    }
}

public enum LedgerScheduledOccurrenceIdentity {
    public static func key(ruleID: UUID, month: LedgerYearMonth) -> String {
        "\(ruleID.uuidString.lowercased()):\(month.key)"
    }
}

/// A due occurrence and the complete draft Storage can atomically persist.
public struct LedgerScheduledOccurrence: Equatable, Sendable {
    public let metadata: LedgerScheduledOccurrenceMetadata
    public let scheduledDate: Date
    public let draft: LedgerEntryDraft

    public init(
        metadata: LedgerScheduledOccurrenceMetadata,
        scheduledDate: Date,
        draft: LedgerEntryDraft
    ) {
        self.metadata = metadata
        self.scheduledDate = scheduledDate
        self.draft = draft
    }

    public var ruleID: UUID { metadata.ruleID }
    public var month: LedgerYearMonth { metadata.month }
    public var occurrenceKey: String { metadata.occurrenceKey }
}

public enum LedgerScheduledEntryPlanner {
    /// Returns every due, not-yet-handled occurrence in ascending month order.
    /// Handled keys must include both existing generated entries and deleted tombstones.
    public static func dueOccurrences(
        for rule: LedgerScheduledEntryRule,
        through now: Date,
        excluding handledKeys: Set<String> = [],
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> [LedgerScheduledOccurrence] {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw LedgerScheduledEntryError.invalidDate
        }
        guard rule.isEnabled else { return [] }
        let currentMonth = try LedgerYearMonth.containing(
            now,
            calendar: calendar,
            timeZone: timeZone
        )
        guard rule.effectiveStartMonth <= currentMonth else { return [] }

        var month = rule.effectiveStartMonth
        var occurrences: [LedgerScheduledOccurrence] = []
        while month <= currentMonth {
            let date = try scheduledDate(
                for: rule.monthlyDay,
                in: month,
                calendar: calendar,
                timeZone: timeZone
            )
            let metadata = LedgerScheduledOccurrenceMetadata(ruleID: rule.id, month: month)
            if date <= now, !handledKeys.contains(metadata.occurrenceKey) {
                let draft = LedgerEntryDraft(
                    bookID: rule.bookID,
                    categoryID: rule.categoryID,
                    kind: rule.kind,
                    amount: rule.amount,
                    date: date,
                    note: rule.note,
                    source: .scheduled,
                    scheduledOccurrence: metadata
                )
                occurrences.append(LedgerScheduledOccurrence(
                    metadata: metadata,
                    scheduledDate: date,
                    draft: draft
                ))
            }
            if month == currentMonth { break }
            month = try month.next()
        }
        return occurrences
    }

    /// Returns the first scheduled date strictly after `now`, or nil while disabled.
    public static func nextExecutionDate(
        for rule: LedgerScheduledEntryRule,
        after now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> Date? {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw LedgerScheduledEntryError.invalidDate
        }
        guard rule.isEnabled else { return nil }
        let currentMonth = try LedgerYearMonth.containing(
            now,
            calendar: calendar,
            timeZone: timeZone
        )
        var month = max(rule.effectiveStartMonth, currentMonth)
        while true {
            let date = try scheduledDate(
                for: rule.monthlyDay,
                in: month,
                calendar: calendar,
                timeZone: timeZone
            )
            if date > now { return date }
            month = try month.next()
        }
    }

    /// Fixed days missing from a month clamp to that month's final local day.
    public static func scheduledDate(
        for monthlyDay: LedgerMonthlyDay,
        in month: LedgerYearMonth,
        calendar: Calendar,
        timeZone: TimeZone
    ) throws -> Date {
        if case let .fixed(day) = monthlyDay, !(1...31).contains(day) {
            throw LedgerScheduledEntryError.invalidMonthlyDay(day)
        }
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        var firstComponents = DateComponents()
        firstComponents.calendar = localCalendar
        firstComponents.timeZone = timeZone
        firstComponents.year = month.year
        firstComponents.month = month.month
        firstComponents.day = 1
        firstComponents.hour = 12
        guard let firstDayAtNoon = localCalendar.date(from: firstComponents),
              let dayRange = localCalendar.range(of: .day, in: .month, for: firstDayAtNoon),
              let finalDay = dayRange.last
        else { throw LedgerScheduledEntryError.dateCalculationFailed }

        let requestedDay: Int = switch monthlyDay {
        case let .fixed(day): min(day, finalDay)
        case .lastDay: finalDay
        }
        var targetComponents = firstComponents
        targetComponents.day = requestedDay
        guard let targetAtNoon = localCalendar.date(from: targetComponents) else {
            throw LedgerScheduledEntryError.dateCalculationFailed
        }
        return localCalendar.startOfDay(for: targetAtNoon)
    }
}
