import Foundation

enum LocalStoreDataProtection {
    static func protectDirectory(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }

    static func protectStoreFamily(at storeURL: URL) throws {
        #if os(iOS)
        for url in StoreUpgradeSnapshot.storeFamilyURLs(for: storeURL)
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
        #endif
    }

    static func protectFile(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }
}

enum StoreUpgradeSnapshot {
    private static let snapshotDirectoryName = "UpgradeSnapshots"

    static func prepareIfNeeded(for storeURL: URL, targetSchemaVersion: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let markerURL = schemaMarkerURL(for: storeURL)
        let recordedVersion = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard recordedVersion != targetSchemaVersion else { return }

        let snapshotsURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        try LocalStoreDataProtection.protectDirectory(at: snapshotsURL)

        let destinationURL = snapshotsURL
            .appendingPathComponent("before-\(targetSchemaVersion)", isDirectory: true)
        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

        let stagingURL = snapshotsURL
            .appendingPathComponent(".before-\(targetSchemaVersion)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        do {
            for sourceURL in storeFamilyURLs(for: storeURL)
            where fileManager.fileExists(atPath: sourceURL.path) {
                let copiedURL = stagingURL.appendingPathComponent(sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: copiedURL)
                try LocalStoreDataProtection.protectFile(at: copiedURL)
            }
            if fileManager.fileExists(atPath: markerURL.path) {
                let previousVersionURL = stagingURL.appendingPathComponent("previous-schema-version")
                try fileManager.copyItem(at: markerURL, to: previousVersionURL)
                try LocalStoreDataProtection.protectFile(at: previousVersionURL)
            }
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            try LocalStoreDataProtection.protectDirectory(at: destinationURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    static func markSuccessfulOpen(for storeURL: URL, schemaVersion: String) throws {
        let markerURL = schemaMarkerURL(for: storeURL)
        try Data("\(schemaVersion)\n".utf8).write(to: markerURL, options: .atomic)
        try LocalStoreDataProtection.protectFile(at: markerURL)
    }

    static func schemaMarkerURL(for storeURL: URL) -> URL {
        URL(fileURLWithPath: "\(storeURL.path).schema-version")
    }

    static func snapshotStoreURL(for storeURL: URL, targetSchemaVersion: String) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent("before-\(targetSchemaVersion)", isDirectory: true)
            .appendingPathComponent(storeURL.lastPathComponent, isDirectory: false)
    }

    static func storeFamilyURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: "\(storeURL.path)-wal"),
            URL(fileURLWithPath: "\(storeURL.path)-shm"),
        ]
    }
}
