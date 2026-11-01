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

enum LedgerSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

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
        var importFormatRawValue: String?
        var importDeduplicationKey: String?
        var importOriginalCategory: String?
        var importOriginalTimestamp: String?
        var importOriginalAmount: String?
        var importOriginalAccount: String?
        var importOriginalBook: String?
        var importOriginalCurrency: String?
        var importOriginalNote: String?
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
            importFormatRawValue: String? = nil,
            importDeduplicationKey: String? = nil,
            importOriginalCategory: String? = nil,
            importOriginalTimestamp: String? = nil,
            importOriginalAmount: String? = nil,
            importOriginalAccount: String? = nil,
            importOriginalBook: String? = nil,
            importOriginalCurrency: String? = nil,
            importOriginalNote: String? = nil,
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
            self.importFormatRawValue = importFormatRawValue
            self.importDeduplicationKey = importDeduplicationKey
            self.importOriginalCategory = importOriginalCategory
            self.importOriginalTimestamp = importOriginalTimestamp
            self.importOriginalAmount = importOriginalAmount
            self.importOriginalAccount = importOriginalAccount
            self.importOriginalBook = importOriginalBook
            self.importOriginalCurrency = importOriginalCurrency
            self.importOriginalNote = importOriginalNote
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

enum LedgerSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            BookRecord.self,
            CategoryRecord.self,
            EntryRecord.self,
            StoreMetadata.self,
            ScheduledRuleVersionRecord.self,
            ScheduledOccurrenceRecord.self,
        ]
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
        var importFormatRawValue: String?
        var importDeduplicationKey: String?
        var importOriginalCategory: String?
        var importOriginalTimestamp: String?
        var importOriginalAmount: String?
        var importOriginalAccount: String?
        var importOriginalBook: String?
        var importOriginalCurrency: String?
        var importOriginalNote: String?
        var scheduledRuleID: UUID?
        var scheduledYear: Int?
        var scheduledMonth: Int?
        var scheduledOccurrenceKey: String?
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
            importFormatRawValue: String? = nil,
            importDeduplicationKey: String? = nil,
            importOriginalCategory: String? = nil,
            importOriginalTimestamp: String? = nil,
            importOriginalAmount: String? = nil,
            importOriginalAccount: String? = nil,
            importOriginalBook: String? = nil,
            importOriginalCurrency: String? = nil,
            importOriginalNote: String? = nil,
            scheduledRuleID: UUID? = nil,
            scheduledYear: Int? = nil,
            scheduledMonth: Int? = nil,
            scheduledOccurrenceKey: String? = nil,
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
            self.importFormatRawValue = importFormatRawValue
            self.importDeduplicationKey = importDeduplicationKey
            self.importOriginalCategory = importOriginalCategory
            self.importOriginalTimestamp = importOriginalTimestamp
            self.importOriginalAmount = importOriginalAmount
            self.importOriginalAccount = importOriginalAccount
            self.importOriginalBook = importOriginalBook
            self.importOriginalCurrency = importOriginalCurrency
            self.importOriginalNote = importOriginalNote
            self.scheduledRuleID = scheduledRuleID
            self.scheduledYear = scheduledYear
            self.scheduledMonth = scheduledMonth
            self.scheduledOccurrenceKey = scheduledOccurrenceKey
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

    @Model
    final class ScheduledRuleVersionRecord {
        var versionID: UUID = UUID()
        var ruleID: UUID = UUID()
        var effectiveYear: Int = 1970
        var effectiveMonth: Int = 1
        var bookID: UUID = UUID()
        var categoryID: UUID = UUID()
        var kindRawValue: String = "expense"
        var amountMinorUnits: Int64 = 0
        var note: String = ""
        var monthlyDayRawValue: String = "fixed"
        var fixedDay: Int?
        var isEnabled: Bool = true
        var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
        var deletedAt: Date?

        init(
            versionID: UUID,
            ruleID: UUID,
            effectiveYear: Int,
            effectiveMonth: Int,
            bookID: UUID,
            categoryID: UUID,
            kindRawValue: String,
            amountMinorUnits: Int64,
            note: String,
            monthlyDayRawValue: String,
            fixedDay: Int?,
            isEnabled: Bool,
            createdAt: Date,
            updatedAt: Date,
            deletedAt: Date? = nil
        ) {
            self.versionID = versionID
            self.ruleID = ruleID
            self.effectiveYear = effectiveYear
            self.effectiveMonth = effectiveMonth
            self.bookID = bookID
            self.categoryID = categoryID
            self.kindRawValue = kindRawValue
            self.amountMinorUnits = amountMinorUnits
            self.note = note
            self.monthlyDayRawValue = monthlyDayRawValue
            self.fixedDay = fixedDay
            self.isEnabled = isEnabled
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class ScheduledOccurrenceRecord {
        var id: UUID = UUID()
        var occurrenceKey: String = ""
        var ruleID: UUID = UUID()
        var year: Int = 1970
        var month: Int = 1
        var entryID: UUID = UUID()
        var scheduledDate: Date = Date(timeIntervalSinceReferenceDate: 0)
        var handledAt: Date = Date(timeIntervalSinceReferenceDate: 0)

        init(
            id: UUID,
            occurrenceKey: String,
            ruleID: UUID,
            year: Int,
            month: Int,
            entryID: UUID,
            scheduledDate: Date,
            handledAt: Date
        ) {
            self.id = id
            self.occurrenceKey = occurrenceKey
            self.ruleID = ruleID
            self.year = year
            self.month = month
            self.entryID = entryID
            self.scheduledDate = scheduledDate
            self.handledAt = handledAt
        }
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LedgerSchemaV1.self, LedgerSchemaV2.self, LedgerSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: LedgerSchemaV1.self, toVersion: LedgerSchemaV2.self),
            MigrationStage.lightweight(fromVersion: LedgerSchemaV2.self, toVersion: LedgerSchemaV3.self),
        ]
    }
}
