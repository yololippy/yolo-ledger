import Foundation

/// Exact rational data for rendering a category's share without rounding in Core.
public struct LedgerStatisticsRatio: Equatable, Sendable {
    public let numeratorMinorUnits: Int64
    public let denominatorMinorUnits: Int64

    public init(numeratorMinorUnits: Int64, denominatorMinorUnits: Int64) {
        self.numeratorMinorUnits = numeratorMinorUnits
        self.denominatorMinorUnits = denominatorMinorUnits
    }
}

public struct LedgerCategoryStatistics: Identifiable, Equatable, Sendable {
    public static let unknownCategoryName = "未知分类"

    public let categoryID: UUID
    public let categoryName: String
    public let isKnownCategory: Bool
    public let amountMinorUnits: Int64
    public let entryCount: Int
    public let share: LedgerStatisticsRatio
    /// Stable IDs in the same deterministic order as the matching ranked entries.
    public let entryIDs: [UUID]

    public var id: UUID { categoryID }

    public init(
        categoryID: UUID,
        categoryName: String,
        isKnownCategory: Bool,
        amountMinorUnits: Int64,
        entryCount: Int,
        share: LedgerStatisticsRatio,
        entryIDs: [UUID]
    ) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isKnownCategory = isKnownCategory
        self.amountMinorUnits = amountMinorUnits
        self.entryCount = entryCount
        self.share = share
        self.entryIDs = entryIDs
    }
}

/// Statistics for one selected half-open date range and one income/expense kind.
public struct LedgerStatisticsSnapshot: Equatable, Sendable {
    public let kind: LedgerEntryKind
    public let dateRange: LedgerDateRange
    public let totalMinorUnits: Int64
    public let entryCount: Int
    public let categories: [LedgerCategoryStatistics]
    /// Entries are ready for UI drill-down and sorted by amount/date/creation/UUID.
    public let rankedEntries: [LedgerEntry]

    public init(
        kind: LedgerEntryKind,
        dateRange: LedgerDateRange,
        totalMinorUnits: Int64,
        entryCount: Int,
        categories: [LedgerCategoryStatistics],
        rankedEntries: [LedgerEntry]
    ) {
        self.kind = kind
        self.dateRange = dateRange
        self.totalMinorUnits = totalMinorUnits
        self.entryCount = entryCount
        self.categories = categories
        self.rankedEntries = rankedEntries
    }
}

public struct LedgerMonthlyTrendPoint: Identifiable, Equatable, Sendable {
    public let dateRange: LedgerDateRange
    public let amountMinorUnits: Int64
    public let entryCount: Int
    /// Stable IDs for drilling into this month without recomputing its boundaries.
    public let entryIDs: [UUID]

    public var id: Date { dateRange.start }

    public init(
        dateRange: LedgerDateRange,
        amountMinorUnits: Int64,
        entryCount: Int,
        entryIDs: [UUID]
    ) {
        self.dateRange = dateRange
        self.amountMinorUnits = amountMinorUnits
        self.entryCount = entryCount
        self.entryIDs = entryIDs
    }
}

/// One selected calendar month plus the six-month trend ending at that month.
public struct LedgerMonthlyStatistics: Equatable, Sendable {
    public let snapshot: LedgerStatisticsSnapshot
    /// Always six points, ordered from oldest month to the selected month.
    public let trend: [LedgerMonthlyTrendPoint]

    public init(
        snapshot: LedgerStatisticsSnapshot,
        trend: [LedgerMonthlyTrendPoint]
    ) {
        self.snapshot = snapshot
        self.trend = trend
    }
}

public enum LedgerStatisticsCalculator {
    private struct CategoryAccumulator {
        var amountMinorUnits: Int64 = 0
        var entryCount = 0
        var entries: [LedgerEntry] = []
    }

    /// Computes totals, category shares, and entry ranking for any half-open date range.
    public static func snapshot(
        entries: [LedgerEntry],
        categories: [LedgerCategory],
        kind: LedgerEntryKind,
        dateRange: LedgerDateRange
    ) throws -> LedgerStatisticsSnapshot {
        try validateDates(in: entries)
        let knownCategoryNames = categoryNames(categories, for: kind)
        var totalMinorUnits: Int64 = 0
        var categoryAccumulators: [UUID: CategoryAccumulator] = [:]
        var matchingEntries: [LedgerEntry] = []

        for entry in entries where entry.kind == kind && dateRange.contains(entry.date) {
            totalMinorUnits = try adding(entry.amount.minorUnits, to: totalMinorUnits)
            var category = categoryAccumulators[entry.categoryID] ?? CategoryAccumulator()
            category.amountMinorUnits = try adding(
                entry.amount.minorUnits,
                to: category.amountMinorUnits
            )
            category.entryCount += 1
            category.entries.append(entry)
            categoryAccumulators[entry.categoryID] = category
            matchingEntries.append(entry)
        }

        let categoryResults = categoryAccumulators.map { categoryID, accumulator in
            let knownName = knownCategoryNames[categoryID]
            return LedgerCategoryStatistics(
                categoryID: categoryID,
                categoryName: knownName ?? LedgerCategoryStatistics.unknownCategoryName,
                isKnownCategory: knownName != nil,
                amountMinorUnits: accumulator.amountMinorUnits,
                entryCount: accumulator.entryCount,
                share: LedgerStatisticsRatio(
                    numeratorMinorUnits: accumulator.amountMinorUnits,
                    denominatorMinorUnits: totalMinorUnits
                ),
                entryIDs: accumulator.entries.sorted(by: entryComesBefore).map(\.id)
            )
        }.sorted(by: categoryComesBefore)

        return LedgerStatisticsSnapshot(
            kind: kind,
            dateRange: dateRange,
            totalMinorUnits: totalMinorUnits,
            entryCount: matchingEntries.count,
            categories: categoryResults,
            rankedEntries: matchingEntries.sorted(by: entryComesBefore)
        )
    }

    /// Computes the selected local calendar month and its fixed six-month trend.
    /// The caller should pass entries covering `sixMonthDateRange` for complete results.
    public static func monthly(
        entries: [LedgerEntry],
        categories: [LedgerCategory],
        kind: LedgerEntryKind,
        monthContaining selectedDate: Date,
        calendar: Calendar = .current
    ) throws -> LedgerMonthlyStatistics {
        let ranges = try sixMonthRanges(
            endingAtMonthContaining: selectedDate,
            calendar: calendar
        )
        let selectedRange = ranges[ranges.count - 1]
        let snapshot = try snapshot(
            entries: entries,
            categories: categories,
            kind: kind,
            dateRange: selectedRange
        )
        let trend = try trendPoints(entries: entries, kind: kind, ranges: ranges)
        return LedgerMonthlyStatistics(snapshot: snapshot, trend: trend)
    }

    /// Range to request from Storage before calling `monthly`.
    public static func sixMonthDateRange(
        endingAtMonthContaining selectedDate: Date,
        calendar: Calendar = .current
    ) throws -> LedgerDateRange {
        let ranges = try sixMonthRanges(
            endingAtMonthContaining: selectedDate,
            calendar: calendar
        )
        return try LedgerDateRange(
            start: ranges[0].start,
            end: ranges[ranges.count - 1].end
        )
    }

    private static func trendPoints(
        entries: [LedgerEntry],
        kind: LedgerEntryKind,
        ranges: [LedgerDateRange]
    ) throws -> [LedgerMonthlyTrendPoint] {
        try validateDates(in: entries)
        var amounts = [Int64](repeating: 0, count: ranges.count)
        var counts = [Int](repeating: 0, count: ranges.count)
        var matchingEntries = [[LedgerEntry]](repeating: [], count: ranges.count)

        for entry in entries where entry.kind == kind {
            guard let index = ranges.firstIndex(where: { $0.contains(entry.date) }) else {
                continue
            }
            amounts[index] = try adding(entry.amount.minorUnits, to: amounts[index])
            counts[index] += 1
            matchingEntries[index].append(entry)
        }
        return ranges.indices.map { index in
            LedgerMonthlyTrendPoint(
                dateRange: ranges[index],
                amountMinorUnits: amounts[index],
                entryCount: counts[index],
                entryIDs: matchingEntries[index].sorted(by: entryComesBefore).map(\.id)
            )
        }
    }

    private static func sixMonthRanges(
        endingAtMonthContaining selectedDate: Date,
        calendar: Calendar
    ) throws -> [LedgerDateRange] {
        let selectedRange = try LedgerDateRanges.range(
            for: .month,
            containing: selectedDate,
            calendar: calendar
        )
        var ranges = [selectedRange]
        var cursor = selectedRange.start
        for _ in 1..<6 {
            guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: cursor) else {
                throw LedgerError.invalidDateRange
            }
            let range = try LedgerDateRanges.range(
                for: .month,
                containing: previousMonth,
                calendar: calendar
            )
            ranges.append(range)
            cursor = range.start
        }
        return ranges.reversed()
    }

    private static func categoryNames(
        _ categories: [LedgerCategory],
        for kind: LedgerEntryKind
    ) -> [UUID: String] {
        var names: [UUID: String] = [:]
        for category in categories where category.kind == kind {
            let normalizedName = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else { continue }
            if let existing = names[category.id] {
                names[category.id] = min(existing, normalizedName)
            } else {
                names[category.id] = normalizedName
            }
        }
        return names
    }

    private static func categoryComesBefore(
        _ left: LedgerCategoryStatistics,
        _ right: LedgerCategoryStatistics
    ) -> Bool {
        if left.amountMinorUnits != right.amountMinorUnits {
            return left.amountMinorUnits > right.amountMinorUnits
        }
        if left.categoryName != right.categoryName {
            return left.categoryName < right.categoryName
        }
        return uuidKey(left.categoryID) < uuidKey(right.categoryID)
    }

    private static func entryComesBefore(_ left: LedgerEntry, _ right: LedgerEntry) -> Bool {
        if left.amount.minorUnits != right.amount.minorUnits {
            return left.amount.minorUnits > right.amount.minorUnits
        }
        if left.date != right.date { return left.date > right.date }
        if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
        return uuidKey(left.id) < uuidKey(right.id)
    }

    private static func validateDates(in entries: [LedgerEntry]) throws {
        for entry in entries {
            guard entry.date.timeIntervalSinceReferenceDate.isFinite,
                  entry.createdAt.timeIntervalSinceReferenceDate.isFinite
            else { throw LedgerError.invalidDate }
        }
    }

    private static func adding(_ amount: Int64, to total: Int64) throws -> Int64 {
        let (result, overflow) = total.addingReportingOverflow(amount)
        guard !overflow else { throw LedgerError.summaryOverflow }
        return result
    }

    private static func uuidKey(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
