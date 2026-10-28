import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct BookListModelTests {
    @Test
    func displaysBooksReturnedByInjectedRepository() async {
        let books = [LedgerBook(id: UUID(), name: "日常账本")]
        let model = BookListModel(repository: FixedBookRepository(books: books))

        await model.load()

        #expect(model.state == .loaded(books))
    }

    @Test
    func emptyRepositoryCompletesWithEmptyState() async {
        let model = BookListModel(repository: FixedBookRepository(books: []))

        await model.load()

        #expect(model.state == .loaded([]))
    }

    @Test
    func failedReadCanBeRetriedSuccessfully() async {
        let books = [LedgerBook(id: UUID(), name: "恢复读取")]
        let model = BookListModel(repository: FailOnceBookRepository(books: books))

        await model.load()
        #expect(model.state == .failed)

        await model.load()
        #expect(model.state == .loaded(books))
    }

    @Test
    func cancelledOlderReadCannotBlockOrOverwriteNewRead() async {
        let repository = ControlledBookRepository()
        let model = BookListModel(repository: repository)
        let older = Task { await model.load() }
        guard await repository.waitForRequestCount(1) else {
            Issue.record("The first repository read did not start.")
            await repository.finishRemainingReads()
            await older.value
            return
        }

        older.cancel()
        let newer = Task { await model.load() }
        guard await repository.waitForRequestCount(2) else {
            Issue.record("Reentering the page must start a replacement read.")
            await repository.finishRemainingReads()
            await older.value
            await newer.value
            return
        }

        let latestBooks = [LedgerBook(id: UUID(), name: "最新账本")]
        await repository.completeRead(1, books: latestBooks)
        await newer.value
        #expect(model.state == .loaded(latestBooks))

        await repository.completeRead(0, books: [])
        await older.value
        #expect(model.state == .loaded(latestBooks))
    }
}

private struct FixedBookRepository: LedgerBookRepository {
    let books: [LedgerBook]

    func fetchBooks() async throws -> [LedgerBook] { books }
}

private actor FailOnceBookRepository: LedgerBookRepository {
    let books: [LedgerBook]
    private var attempts = 0

    init(books: [LedgerBook]) {
        self.books = books
    }

    func fetchBooks() async throws -> [LedgerBook] {
        attempts += 1
        if attempts == 1 { throw ReadFailure.unavailable }
        return books
    }
}

private enum ReadFailure: Error {
    case unavailable
}

/// Ignores cancellation until explicitly completed, like a slow external adapter.
private actor ControlledBookRepository: LedgerBookRepository {
    private var reads: [Int: CheckedContinuation<[LedgerBook], any Error>] = [:]
    private var requestCount = 0

    func fetchBooks() async throws -> [LedgerBook] {
        let index = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            reads[index] = continuation
        }
    }

    func waitForRequestCount(_ count: Int) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while requestCount < count, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return requestCount >= count
    }

    func completeRead(_ index: Int, books: [LedgerBook]) {
        reads.removeValue(forKey: index)?.resume(returning: books)
    }

    func finishRemainingReads() {
        let pending = reads.values
        reads.removeAll()
        for read in pending { read.resume(throwing: ReadFailure.unavailable) }
    }
}
