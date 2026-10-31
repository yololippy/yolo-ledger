import CryptoKit
import Foundation
import YoloLedgerCore

public typealias LedgerMeowImportHandler = @Sendable (
    [LedgerMeowImportPlan]
) async throws -> LedgerMeowImportBatchReport

public struct LedgerMeowImportBatchReport: Equatable, Sendable {
    public let batchID: UUID
    public let backupURL: URL
    public let submittedRecordCount: Int
    public let importedEntryCount: Int
    public let skippedDuplicateCount: Int
    public let createdBookCount: Int
    public let createdCategoryCount: Int
    public let importedExpenseCount: Int
    public let importedIncomeCount: Int
    public let importedExpenseTotalMinorUnits: Decimal
    public let importedIncomeTotalMinorUnits: Decimal
    public let completedAt: Date

    public init(
        batchID: UUID,
        backupURL: URL,
        submittedRecordCount: Int,
        importedEntryCount: Int,
        skippedDuplicateCount: Int,
        createdBookCount: Int,
        createdCategoryCount: Int,
        importedExpenseCount: Int,
        importedIncomeCount: Int,
        importedExpenseTotalMinorUnits: Decimal,
        importedIncomeTotalMinorUnits: Decimal,
        completedAt: Date
    ) {
        self.batchID = batchID
        self.backupURL = backupURL
        self.submittedRecordCount = submittedRecordCount
        self.importedEntryCount = importedEntryCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.createdBookCount = createdBookCount
        self.createdCategoryCount = createdCategoryCount
        self.importedExpenseCount = importedExpenseCount
        self.importedIncomeCount = importedIncomeCount
        self.importedExpenseTotalMinorUnits = importedExpenseTotalMinorUnits
        self.importedIncomeTotalMinorUnits = importedIncomeTotalMinorUnits
        self.completedAt = completedAt
    }
}

public enum LedgerMeowImportStorageError: Error, Equatable, Sendable, LocalizedError {
    case emptyBatch
    case planContainsIssues(planIndex: Int, issueCount: Int)
    case inconsistentPlan(planIndex: Int, reason: String)
    case deduplicationConflict
    case identifierCollision(entity: String, id: UUID)
    case sortOrderOverflow(entity: String)
    case backupFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyBatch:
            "没有可导入的喵喵记账文件。"
        case let .planContainsIssues(planIndex, issueCount):
            "第 \(planIndex + 1) 个文件仍有 \(issueCount) 个解析问题，未写入任何数据。"
        case let .inconsistentPlan(planIndex, reason):
            "第 \(planIndex + 1) 个导入计划不一致：\(reason)"
        case .deduplicationConflict:
            "导入去重标识与已有账目内容冲突，未写入任何数据。"
        case let .identifierCollision(entity, id):
            "无法创建\(entity)：稳定标识 \(id.uuidString) 已被其他数据使用。"
        case let .sortOrderOverflow(entity):
            "无法创建\(entity)：排序编号超出可保存范围。"
        case let .backupFailed(message):
            "导入前本地备份失败：\(message)"
        }
    }
}

struct LedgerMeowImportPreparedRecord: Sendable {
    let record: LedgerMeowImportRecord
    let entryID: UUID
    let normalizedBookName: String
    let normalizedCategoryName: String
}

struct LedgerMeowImportPreparation: Sendable {
    let submittedRecordCount: Int
    let duplicateRecordCountWithinBatch: Int
    let uniqueRecords: [LedgerMeowImportPreparedRecord]
}

struct LedgerMeowCategoryMappingKey: Hashable, Sendable {
    let kind: LedgerEntryKind
    let name: String
}

enum LedgerMeowImportStableID {
    static func book(name: String) -> UUID {
        make(namespace: "meow-ledger-book-v1", value: name)
    }

    static func category(kind: LedgerEntryKind, name: String) -> UUID {
        make(namespace: "meow-ledger-category-v1", value: "\(kind.rawValue)\u{0}\(name)")
    }

    static func entry(deduplicationKey: String) -> UUID {
        make(namespace: "meow-ledger-entry-v1", value: deduplicationKey)
    }

    private static func make(namespace: String, value: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace)\u{0}\(value)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum LedgerMeowImportPlanValidator {
    static func prepare(_ plans: [LedgerMeowImportPlan]) throws -> LedgerMeowImportPreparation {
        guard !plans.isEmpty else { throw LedgerMeowImportStorageError.emptyBatch }
        var submittedRecordCount = 0
        var duplicateRecordCount = 0
        var recordsByKey: [String: LedgerMeowImportPreparedRecord] = [:]
        var orderedRecords: [LedgerMeowImportPreparedRecord] = []

        for (planIndex, plan) in plans.enumerated() {
            guard plan.issues.isEmpty else {
                throw LedgerMeowImportStorageError.planContainsIssues(
                    planIndex: planIndex,
                    issueCount: plan.issues.count
                )
            }
            try validatePreview(plan, planIndex: planIndex)
            submittedRecordCount += plan.records.count
            var occurrences: [LedgerMeowSourceFields: Int] = [:]

            for record in plan.records {
                let occurrence = occurrences[record.fields, default: 0] + 1
                occurrences[record.fields] = occurrence
                try validate(record, occurrence: occurrence, planIndex: planIndex)
                let prepared = LedgerMeowImportPreparedRecord(
                    record: record,
                    entryID: LedgerMeowImportStableID.entry(
                        deduplicationKey: record.importMetadata.deduplicationKey
                    ),
                    normalizedBookName: try LedgerValidation.normalizedName(record.fields.book),
                    normalizedCategoryName: try LedgerValidation.normalizedName(record.fields.category)
                )
                let key = record.importMetadata.deduplicationKey
                if let existing = recordsByKey[key] {
                    guard semanticallyEqual(existing.record, record) else {
                        throw LedgerMeowImportStorageError.deduplicationConflict
                    }
                    duplicateRecordCount += 1
                } else {
                    recordsByKey[key] = prepared
                    orderedRecords.append(prepared)
                }
            }
        }
        return LedgerMeowImportPreparation(
            submittedRecordCount: submittedRecordCount,
            duplicateRecordCountWithinBatch: duplicateRecordCount,
            uniqueRecords: orderedRecords
        )
    }

    private static func validate(
        _ record: LedgerMeowImportRecord,
        occurrence: Int,
        planIndex: Int
    ) throws {
        let metadata = record.importMetadata
        let expectedKey = LedgerMeowImportIdentity.deduplicationKey(
            for: record.fields,
            occurrence: occurrence
        )
        guard record.sourceLine > 1,
              record.date.timeIntervalSinceReferenceDate.isFinite,
              metadata.format == .meowLedgerCSVV1,
              metadata.deduplicationKey == expectedKey,
              metadata.originalCategory == record.fields.category,
              metadata.originalTimestamp == record.fields.timestamp,
              metadata.originalAmount == record.fields.amount,
              metadata.originalAccount == record.fields.account,
              metadata.originalBook == record.fields.book,
              metadata.originalCurrency == record.fields.currency,
              metadata.originalNote == record.fields.note
        else {
            throw LedgerMeowImportStorageError.inconsistentPlan(
                planIndex: planIndex,
                reason: "记录字段、时间或去重标识与解析结果不一致"
            )
        }
    }

    private static func validatePreview(
        _ plan: LedgerMeowImportPlan,
        planIndex: Int
    ) throws {
        let expenseRecords = plan.records.filter { $0.kind == .expense }
        let incomeRecords = plan.records.filter { $0.kind == .income }
        guard plan.preview.validRecordCount == plan.records.count,
              plan.preview.invalidRowCount == 0,
              plan.preview.expenseRecordCount == expenseRecords.count,
              plan.preview.incomeRecordCount == incomeRecords.count,
              plan.preview.distinctBookCount == Set(plan.records.map(\.fields.book)).count,
              plan.preview.distinctCategoryCount == Set(plan.records.map(\.fields.category)).count,
              plan.preview.distinctAccountCount == Set(plan.records.map(\.fields.account)).count,
              plan.preview.distinctCurrencyCount == Set(plan.records.map(\.fields.currency)).count
        else {
            throw LedgerMeowImportStorageError.inconsistentPlan(
                planIndex: planIndex,
                reason: "预览统计与记录不一致"
            )
        }
    }

    private static func semanticallyEqual(
        _ left: LedgerMeowImportRecord,
        _ right: LedgerMeowImportRecord
    ) -> Bool {
        left.fields == right.fields
            && left.kind == right.kind
            && left.amount == right.amount
            && left.date == right.date
            && left.importMetadata == right.importMetadata
    }
}

enum StoreImportSnapshot {
    private static let directoryName = "ImportSnapshots"

    static func create(
        for storeURL: URL,
        batchID: UUID,
        createdAt: Date
    ) throws -> URL {
        let fileManager = FileManager.default
        let snapshotsURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(directoryName, isDirectory: true)
        let destinationURL = snapshotsURL
            .appendingPathComponent(batchID.uuidString.lowercased(), isDirectory: true)
        let stagingURL = snapshotsURL
            .appendingPathComponent(".\(batchID.uuidString.lowercased())-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
            try LocalStoreDataProtection.protectDirectory(at: snapshotsURL)
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)

            var copiedStoreFile = false
            for sourceURL in StoreUpgradeSnapshot.storeFamilyURLs(for: storeURL)
            where fileManager.fileExists(atPath: sourceURL.path) {
                let copiedURL = stagingURL.appendingPathComponent(sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: copiedURL)
                try LocalStoreDataProtection.protectFile(at: copiedURL)
                if sourceURL == storeURL { copiedStoreFile = true }
            }
            guard copiedStoreFile else { throw CocoaError(.fileNoSuchFile) }

            let schemaMarkerURL = StoreUpgradeSnapshot.schemaMarkerURL(for: storeURL)
            if fileManager.fileExists(atPath: schemaMarkerURL.path) {
                let copiedMarkerURL = stagingURL.appendingPathComponent(schemaMarkerURL.lastPathComponent)
                try fileManager.copyItem(at: schemaMarkerURL, to: copiedMarkerURL)
                try LocalStoreDataProtection.protectFile(at: copiedMarkerURL)
            }

            let manifest = ImportSnapshotManifest(
                batchID: batchID,
                createdAt: createdAt,
                schemaVersion: LocalLedgerStore.currentSchemaVersion,
                storeFilename: storeURL.lastPathComponent
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestURL = stagingURL.appendingPathComponent("manifest.json", isDirectory: false)
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            try LocalStoreDataProtection.protectFile(at: manifestURL)

            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            try LocalStoreDataProtection.protectDirectory(at: destinationURL)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw LedgerMeowImportStorageError.backupFailed(message: error.localizedDescription)
        }
    }

    private struct ImportSnapshotManifest: Codable {
        let batchID: UUID
        let createdAt: Date
        let schemaVersion: String
        let storeFilename: String
    }
}
