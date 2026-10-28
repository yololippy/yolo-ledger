import Observation
import YoloLedgerCore

enum BookListState: Equatable {
    case idle
    case loading
    case loaded([LedgerBook])
    case failed
}

@MainActor
@Observable
final class BookListModel {
    private(set) var state: BookListState = .idle
    private let repository: any LedgerBookRepository
    private var requestGeneration = 0

    init(repository: any LedgerBookRepository) {
        self.repository = repository
    }

    func load() async {
        requestGeneration &+= 1
        let generation = requestGeneration
        state = .loading

        do {
            let books = try await repository.fetchBooks()
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            state = .loaded(books)
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            state = .idle
        } catch {
            guard requestGeneration == generation else { return }
            state = .failed
        }
    }
}
