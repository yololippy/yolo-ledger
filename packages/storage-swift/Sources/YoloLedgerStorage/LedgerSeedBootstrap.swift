import Foundation
import SwiftData
import YoloLedgerCore

/// Seed-data revisions are independent of the database schema version.
enum LedgerSeedBootstrap {
    private static let choicesV1Key = "starter-choices-v1"
    private static let categoriesV2Key = "starter-categories-v2"
    private static let legacyOtherExpenseID = UUID(uuidString: "A20E127A-36F6-401A-A6E3-000000000105")!
    private static let seedTimestamp = Date(timeIntervalSinceReferenceDate: 0)

    static func initialize(in context: ModelContext) throws {
        do {
            if try !hasMarker(choicesV1Key, in: context) {
                try initializeChoices(in: context)
                context.insert(LedgerSchemaV1.StoreMetadata(key: choicesV1Key))
            }
            if try !hasMarker(categoriesV2Key, in: context) {
                try upgradeCategories(in: context)
                context.insert(LedgerSchemaV1.StoreMetadata(key: categoriesV2Key))
            }
            // Keep data and revision markers in one commit; reopening a current store is read-only.
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func hasMarker(_ key: String, in context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<LedgerSchemaV1.StoreMetadata>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    private static func initializeChoices(in context: ModelContext) throws {
        let bookIDs = Set(try context.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>()).map(\.id))
        for (order, book) in LedgerSeedData.books.enumerated() where !bookIDs.contains(book.id) {
            context.insert(LedgerSchemaV1.BookRecord(
                id: book.id,
                name: book.name,
                sortOrder: order,
                createdAt: seedTimestamp,
                updatedAt: seedTimestamp
            ))
        }
        let categoryIDs = Set(try context.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>()).map(\.id))
        for (order, category) in LedgerSeedData.categories.enumerated() where !categoryIDs.contains(category.id) {
            context.insert(LedgerSchemaV1.CategoryRecord(
                id: category.id,
                name: category.name,
                kindRawValue: category.kind.rawValue,
                sortOrder: order,
                createdAt: seedTimestamp,
                updatedAt: seedTimestamp
            ))
        }
    }

    private static func upgradeCategories(in context: ModelContext) throws {
        let upgradeTimestamp = Date()
        let records = try context.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>())
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for (order, category) in LedgerSeedData.categories.enumerated() {
            if let existing = recordsByID[category.id] {
                var changed = existing.sortOrder != order
                existing.sortOrder = order
                if category.id == legacyOtherExpenseID && existing.name == "其他支出" {
                    existing.name = category.name
                    changed = true
                }
                if changed { existing.updatedAt = max(existing.updatedAt, upgradeTimestamp) }
            } else {
                context.insert(LedgerSchemaV1.CategoryRecord(
                    id: category.id,
                    name: category.name,
                    kindRawValue: category.kind.rawValue,
                    sortOrder: order,
                    createdAt: seedTimestamp,
                    updatedAt: seedTimestamp
                ))
            }
        }
    }
}
