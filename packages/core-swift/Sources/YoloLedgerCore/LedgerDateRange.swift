import Foundation

public enum LedgerPeriod: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case year
}

/// A half-open interval: start is included and end belongs to the next period.
public struct LedgerDateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) throws {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite,
              start < end
        else { throw LedgerError.invalidDateRange }
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

public enum LedgerDateRanges {
    /// Calendar.current supplies the device's current local time zone and week preferences.
    /// Inject a calendar for deterministic calculations; do not approximate local days as 86400 seconds.
    public static func range(
        for period: LedgerPeriod,
        containing date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> LedgerDateRange {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw LedgerError.invalidDate }
        let component: Calendar.Component = switch period {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            throw LedgerError.invalidDateRange
        }
        return try LedgerDateRange(start: interval.start, end: interval.end)
    }
}
