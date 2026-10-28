import Foundation
import SwiftData

enum LedgerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [BookRecord.self, CategoryRecord.self, EntryRecord.self, StoreMetadata.self]
    }

    @Model
    final class BookRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var sortOrder: Int

        init(id: UUID, name: String, sortOrder: Int) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class CategoryRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var kindRawValue: String
        var sortOrder: Int

        init(id: UUID, name: String, kindRawValue: String, sortOrder: Int) {
            self.id = id
            self.name = name
            self.kindRawValue = kindRawValue
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class EntryRecord {
        @Attribute(.unique) var id: UUID
        var bookID: UUID
        var categoryID: UUID
        var kindRawValue: String
        var amountMinorUnits: Int64
        var occurredAt: Date
        var note: String
        var sourceRawValue: String
        var createdAt: Date
        var updatedAt: Date

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
            updatedAt: Date
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
        }
    }

    @Model
    final class StoreMetadata {
        @Attribute(.unique) var key: String

        init(key: String) {
            self.key = key
        }
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
