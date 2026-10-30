import Foundation
import SwiftData

public enum LedgerSyncMode: Equatable, Sendable {
    case local
    case iCloudPrivate(containerIdentifier: String)
}

public enum YoloLedgerICloud {
    public static let containerIdentifier = "iCloud.com.yololedger.app"
    public static let syncMode: LedgerSyncMode = .iCloudPrivate(
        containerIdentifier: containerIdentifier
    )
}

public enum LedgerStorageError: Error, Equatable, Sendable, LocalizedError {
    case invalidStoreURL
    case invalidStoredValue(entity: String, field: String)

    public var errorDescription: String? {
        switch self {
        case .invalidStoreURL:
            "本地账目数据库需要一个有效的文件路径。"
        case let .invalidStoredValue(entity, field):
            "本地数据无法读取：\(entity) 的 \(field) 无效。"
        }
    }
}

enum LocalLedgerStore {
    static let currentSchemaVersion = "1.1.0"

    static func makeContainer(
        at storeURL: URL,
        syncMode: LedgerSyncMode = .local
    ) throws -> ModelContainer {
        guard storeURL.isFileURL, !storeURL.hasDirectoryPath else {
            throw LedgerStorageError.invalidStoreURL
        }
        let storeDirectory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        try LocalStoreDataProtection.protectDirectory(at: storeDirectory)
        try StoreUpgradeSnapshot.prepareIfNeeded(
            for: storeURL,
            targetSchemaVersion: currentSchemaVersion
        )
        let schema = Schema(versionedSchema: LedgerSchemaV1.self)
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase
        let configurationName: String
        switch syncMode {
        case .local:
            cloudKitDatabase = .none
            configurationName = "YoloLedgerLocal"
        case let .iCloudPrivate(containerIdentifier):
            cloudKitDatabase = .private(containerIdentifier)
            configurationName = "YoloLedgerCloud"
        }
        let configuration = ModelConfiguration(
            configurationName,
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: cloudKitDatabase
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: LedgerMigrationPlan.self,
            configurations: [configuration]
        )
        try LocalStoreDataProtection.protectStoreFamily(at: storeURL)
        try StoreUpgradeSnapshot.markSuccessfulOpen(
            for: storeURL,
            schemaVersion: currentSchemaVersion
        )
        return container
    }
}
