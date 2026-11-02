import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct LedgerStatisticsControllerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test
    func loadUsesOnlyTheExactSixMonthRangeAndKeepsEmptyMonths() async throws {
        let selectedMonth = date(2026, 6, 18)
        let bookID = UUID()
        let category = LedgerCategory(id: UUID(), name: "餐饮", kind: .expense)
        let current = try entry(
            id: UUID(), bookID: bookID, category: category,
            kind: .expense, amount: "18.50", date: date(2026, 6, 8)
        )
        let previous = try entry(
            id: UUID(), bookID: bookID, category: category,
            kind: .expense, amount: "20.00", date: date(2026, 4, 9)
        )
        let repository = StatisticsTestRepository(entriesByBook: [bookID: [current, previous]])
        let controller = LedgerStatisticsController(repository: repository)

        await controller.load(
            bookID: bookID,
            monthContaining: selectedMonth,
            categories: [category],
            calendar: calendar
        )

        let expectedRange = try LedgerStatisticsCalculator.sixMonthDateRange(
            endingAtMonthContaining: selectedMonth,
            calendar: calendar
        )
        #expect(await repository.boundedReads == 1)
        #expect(await repository.unboundedReads == 0)
        #expect(await repository.lastRange == expectedRange)
        #expect(controller.statistics?.snapshot.totalMinorUnits == 1_850)
        #expect(controller.statistics?.trend.map(\.amountMinorUnits) == [0, 0, 0, 2_000, 0, 1_850])
        #expect(controller.entries(for: [previous.id, current.id]) == [previous, current])
        #expect(controller.loadError == nil)
    }

    @Test
    func switchingKindRecalculatesIncomeWithoutChangingTheBrowseMonth() async throws {
        let selectedMonth = date(2026, 6, 12)
        let bookID = UUID()
        let expenseCategory = LedgerCategory(id: UUID(), name: "餐饮", kind: .expense)
        let incomeCategory = LedgerCategory(id: UUID(), name: "工资", kind: .income)
        let entries = [
            try entry(id: UUID(), bookID: bookID, category: expenseCategory, kind: .expense, amount: "12", date: selectedMonth),
            try entry(id: UUID(), bookID: bookID, category: incomeCategory, kind: .income, amount: "5000", date: selectedMonth),
        ]
        let controller = LedgerStatisticsController(
            repository: StatisticsTestRepository(entriesByBook: [bookID: entries])
        )
        controller.selectKind(.income)

        await controller.load(
            bookID: bookID,
            monthContaining: selectedMonth,
            categories: [expenseCategory, incomeCategory],
            calendar: calendar
        )

        #expect(controller.kind == .income)
        let expectedMonthStart = try LedgerDateRanges.range(
            for: .month,
            containing: selectedMonth,
            calendar: calendar
        ).start
        #expect(controller.context?.monthStart == expectedMonthStart)
        #expect(controller.statistics?.snapshot.totalMinorUnits == 500_000)
        #expect(controller.statistics?.snapshot.categories.map(\.categoryName) == ["工资"])
    }

    @Test
    func aSlowOlderRequestCannotOverwriteTheNewestBook() async throws {
        let oldBookID = UUID()
        let newBookID = UUID()
        let category = LedgerCategory(id: UUID(), name: "其它", kind: .expense)
        let month = date(2026, 6, 10)
        let oldEntry = try entry(id: UUID(), bookID: oldBookID, category: category, kind: .expense, amount: "10", date: month)
        let newEntry = try entry(id: UUID(), bookID: newBookID, category: category, kind: .expense, amount: "99", date: month)
        let repository = StatisticsTestRepository(
            entriesByBook: [oldBookID: [oldEntry], newBookID: [newEntry]],
            delayedBookID: oldBookID
        )
        let controller = LedgerStatisticsController(repository: repository)

        let older = Task {
            await controller.load(
                bookID: oldBookID,
                monthContaining: month,
                categories: [category],
                calendar: calendar
            )
        }
        await repository.waitUntilDelayedReadStarts()
        await controller.load(
            bookID: newBookID,
            monthContaining: month,
            categories: [category],
            calendar: calendar
        )
        await repository.releaseDelayedRead()
        await older.value

        #expect(controller.context?.bookID == newBookID)
        #expect(controller.statistics?.snapshot.totalMinorUnits == 9_900)
        #expect(controller.entries(for: [newEntry.id]) == [newEntry])
        #expect(controller.entries(for: [oldEntry.id]).isEmpty)
    }

    @Test
    func retryKeepsAValidSameContextSnapshotWhileShowingTheError() async throws {
        let bookID = UUID()
        let category = LedgerCategory(id: UUID(), name: "交通", kind: .expense)
        let month = date(2026, 6, 7)
        let saved = try entry(id: UUID(), bookID: bookID, category: category, kind: .expense, amount: "32", date: month)
        let repository = StatisticsTestRepository(entriesByBook: [bookID: [saved]])
        let controller = LedgerStatisticsController(repository: repository)

        await controller.load(bookID: bookID, monthContaining: month, categories: [category], calendar: calendar)
        await repository.setReadFailure(true)
        await controller.load(bookID: bookID, monthContaining: month, categories: [category], calendar: calendar)

        #expect(controller.statistics?.snapshot.totalMinorUnits == 3_200)
        #expect(controller.loadError == "统计测试读取失败。")
        #expect(!controller.isLoading)

        await repository.setReadFailure(false)
        await controller.load(bookID: bookID, monthContaining: month, categories: [category], calendar: calendar)
        #expect(controller.loadError == nil)
        #expect(controller.statistics?.snapshot.totalMinorUnits == 3_200)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func entry(
        id: UUID,
        bookID: UUID,
        category: LedgerCategory,
        kind: LedgerEntryKind,
        amount: String,
        date: Date
    ) throws -> LedgerEntry {
        let draft = LedgerEntryDraft(
            bookID: bookID,
            categoryID: category.id,
            kind: kind,
            amount: try LedgerAmount(input: amount),
            date: date,
            note: category.name
        )
        return LedgerEntry(id: id, draft: draft, createdAt: date, updatedAt: date)
    }
}

private actor StatisticsTestRepository: LedgerRepository {
    var boundedReads = 0
    var unboundedReads = 0
    var lastRange: LedgerDateRange?

    private let entriesByBook: [UUID: [LedgerEntry]]
    private let delayedBookID: UUID?
    private var delayedReadStarted = false
    private var delayedReadContinuation: CheckedContinuation<Void, Never>?
    private var readFailure = false

    init(entriesByBook: [UUID: [LedgerEntry]], delayedBookID: UUID? = nil) {
        self.entriesByBook = entriesByBook
        self.delayedBookID = delayedBookID
    }

    func setReadFailure(_ value: Bool) { readFailure = value }

    func waitUntilDelayedReadStarts() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !delayedReadStarted, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func releaseDelayedRead() {
        delayedReadContinuation?.resume()
        delayedReadContinuation = nil
    }

    func fetchBooks() async throws -> [LedgerBook] { [LedgerSeedData.defaultBook] }
    func fetchCategories() async throws -> [LedgerCategory] { LedgerSeedData.categories }

    func fetchEntries(bookID: UUID?) async throws -> [LedgerEntry] {
        unboundedReads += 1
        if readFailure { throw StatisticsTestError.readFailed }
        if let bookID { return entriesByBook[bookID] ?? [] }
        return entriesByBook.values.flatMap { $0 }
    }

    func fetchEntries(bookID: UUID, dateRange: LedgerDateRange) async throws -> [LedgerEntry] {
        boundedReads += 1
        lastRange = dateRange
        if bookID == delayedBookID {
            delayedReadStarted = true
            await withCheckedContinuation { delayedReadContinuation = $0 }
        }
        if readFailure { throw StatisticsTestError.readFailed }
        return (entriesByBook[bookID] ?? []).filter { dateRange.contains($0.date) }
    }

    func createEntry(_ draft: LedgerEntryDraft, id: UUID) async throws -> LedgerEntry {
        throw StatisticsTestError.unsupported
    }
    func updateEntry(id: UUID, draft: LedgerEntryDraft) async throws -> LedgerEntry {
        throw StatisticsTestError.unsupported
    }
    func deleteEntry(id: UUID) async throws { throw StatisticsTestError.unsupported }
    func createBook(name: String, id: UUID) async throws -> LedgerBook { throw StatisticsTestError.unsupported }
    func renameBook(id: UUID, name: String) async throws -> LedgerBook { throw StatisticsTestError.unsupported }
}

private enum StatisticsTestError: LocalizedError {
    case readFailed
    case unsupported

    var errorDescription: String? {
        switch self {
        case .readFailed: "统计测试读取失败。"
        case .unsupported: "测试不支持此操作。"
        }
    }
}
