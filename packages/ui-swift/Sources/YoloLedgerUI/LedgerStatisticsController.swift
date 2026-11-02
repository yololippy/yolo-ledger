import Foundation
import Observation
import YoloLedgerCore

struct LedgerStatisticsContext: Equatable, Sendable {
    let bookID: UUID
    let monthStart: Date
    let kind: LedgerEntryKind
}

@MainActor
@Observable
final class LedgerStatisticsController {
    private(set) var kind: LedgerEntryKind = .expense
    private(set) var statistics: LedgerMonthlyStatistics?
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var context: LedgerStatisticsContext?

    private let repository: any LedgerRepository
    private var entriesByID: [UUID: LedgerEntry] = [:]
    private var loadGeneration = 0

    init(repository: any LedgerRepository) {
        self.repository = repository
    }

    func selectKind(_ kind: LedgerEntryKind) {
        self.kind = kind
    }

    func load(
        bookID: UUID,
        monthContaining selectedMonth: Date,
        categories: [LedgerCategory],
        calendar: Calendar = .current
    ) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let monthRange: LedgerDateRange
        let requestContext: LedgerStatisticsContext

        do {
            monthRange = try LedgerDateRanges.range(
                for: .month,
                containing: selectedMonth,
                calendar: calendar
            )
            requestContext = LedgerStatisticsContext(
                bookID: bookID,
                monthStart: monthRange.start,
                kind: kind
            )
        } catch {
            guard generation == loadGeneration else { return }
            statistics = nil
            entriesByID = [:]
            context = nil
            loadError = Self.message(for: error)
            return
        }

        if context != requestContext {
            statistics = nil
            entriesByID = [:]
        }
        isLoading = true
        loadError = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let dateRange = try LedgerStatisticsCalculator.sixMonthDateRange(
                endingAtMonthContaining: monthRange.start,
                calendar: calendar
            )
            let entries = try await repository.fetchEntries(
                bookID: bookID,
                dateRange: dateRange
            )
            let result = try LedgerStatisticsCalculator.monthly(
                entries: entries,
                categories: categories,
                kind: requestContext.kind,
                monthContaining: monthRange.start,
                calendar: calendar
            )
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            statistics = result
            entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            context = requestContext
        } catch is CancellationError {
            // The next context owns the statistics snapshot.
        } catch {
            guard generation == loadGeneration else { return }
            loadError = Self.message(for: error)
        }
    }

    func entries(for ids: [UUID]) -> [LedgerEntry] {
        ids.compactMap { entriesByID[$0] }
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "统计暂时无法读取，请稍后重试。"
    }
}
