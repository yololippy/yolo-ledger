import Foundation
import XCTest
import YoloLedgerCore

final class LedgerValidationTests: XCTestCase {
    private func draft(
        bookID: UUID = LedgerSeedData.defaultBook.id,
        categoryID: UUID = LedgerSeedData.categories[0].id,
        kind: LedgerEntryKind = .expense,
        date: Date = Date()
    ) throws -> LedgerEntryDraft {
        LedgerEntryDraft(bookID: bookID, categoryID: categoryID, kind: kind, amount: try LedgerAmount(input: "12.34"), date: date)
    }

    func testNamesNormalizeWhitespaceAndRejectBlankNames() throws {
        XCTAssertEqual(try LedgerValidation.normalizedName(" \n家庭账本\t"), "家庭账本")
        for name in ["", " \n\t", "\u{00A0}\u{3000}"] {
            XCTAssertThrowsError(try LedgerValidation.normalizedName(name)) { error in
                XCTAssertEqual(error as? LedgerError, .emptyName)
            }
        }
    }

    func testValidDraftUsesExistingBookAndMatchingCategory() throws {
        XCTAssertNoThrow(try LedgerValidation.validate(draft(), books: LedgerSeedData.books, categories: LedgerSeedData.categories))
        let category = LedgerSeedData.categories.first { $0.kind == .income }!
        XCTAssertNoThrow(try LedgerValidation.validate(draft(categoryID: category.id, kind: .income), books: LedgerSeedData.books, categories: LedgerSeedData.categories))
    }

    func testMissingReferencesProduceSpecificErrors() throws {
        let missingBook = UUID()
        XCTAssertThrowsError(try LedgerValidation.validate(draft(bookID: missingBook), books: LedgerSeedData.books, categories: LedgerSeedData.categories)) { error in
            XCTAssertEqual(error as? LedgerError, .bookNotFound(missingBook))
        }
        let missingCategory = UUID()
        XCTAssertThrowsError(try LedgerValidation.validate(draft(categoryID: missingCategory), books: LedgerSeedData.books, categories: LedgerSeedData.categories)) { error in
            XCTAssertEqual(error as? LedgerError, .categoryNotFound(missingCategory))
        }
    }

    func testIncomeCannotUseExpenseCategory() throws {
        XCTAssertThrowsError(try LedgerValidation.validate(draft(kind: .income), books: LedgerSeedData.books, categories: LedgerSeedData.categories)) { error in
            XCTAssertEqual(error as? LedgerError, .categoryKindMismatch)
        }
    }

    func testInvalidDatesAreRejectedBeforePersistence() throws {
        XCTAssertThrowsError(try LedgerValidation.validate(draft(date: Date(timeIntervalSinceReferenceDate: .nan)), books: LedgerSeedData.books, categories: LedgerSeedData.categories)) { error in
            XCTAssertEqual(error as? LedgerError, .invalidDate)
        }
    }

    func testSeedIdentifiersAreStableAndUniqueAcrossKinds() {
        let categories = LedgerSeedData.categories
        let identifiers = LedgerSeedData.books.map(\.id) + categories.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(categories.contains { $0.kind == .income })
        XCTAssertTrue(categories.contains { $0.kind == .expense })
        XCTAssertEqual(LedgerSeedData.books.map(\.id), [LedgerSeedData.defaultBook.id])
    }
}
