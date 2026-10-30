import Foundation
import SwiftData

enum LedgerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    static var models: [any PersistentModel.Type] {
        [BookRecord.self, CategoryRecord.self, EntryRecord.self, StoreMetadata.self]
    }

    @Model
    final class BookRecord {
        var id: UUID = UUID()
        var name: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var deletedAt: Date?

        init(
            id: UUID,
            name: String,
            sortOrder: Int,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class CategoryRecord {
        var id: UUID = UUID()
        var name: String = ""
        var kindRawValue: String = "expense"
        var sortOrder: Int = 0
        var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var deletedAt: Date?

        init(
            id: UUID,
            name: String,
            kindRawValue: String,
            sortOrder: Int,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class EntryRecord {
        var id: UUID = UUID()
        var bookID: UUID = UUID()
        var categoryID: UUID = UUID()
        var kindRawValue: String = "expense"
        var amountMinorUnits: Int64 = 0
        var occurredAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var note: String = ""
        var sourceRawValue: String = "manual"
        var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var deletedAt: Date?

        init(
            id: UUID,
            bookID: UUID,
            categoryID: UUID,
            kindRawValue: String,
            amountMinorUnits: Int64,
            occurredAt: Date,
            note: String,
            sourceRawValue: String,
            createdAt: Date,
            updatedAt: Date,
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.bookID = bookID
            self.categoryID = categoryID
            self.kindRawValue = kindRawValue
            self.amountMinorUnits = amountMinorUnits
            self.occurredAt = occurredAt
            self.note = note
            self.sourceRawValue = sourceRawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class StoreMetadata {
        var key: String = ""

        init(key: String) {
            self.key = key
        }
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
