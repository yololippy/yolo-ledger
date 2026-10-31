import Foundation

/// Exchanges ledger changes with a user-selected folder without exposing a concrete file format.
///
/// The caller must obtain and retain any platform-specific permission for `folderURL` before
/// invoking this contract. Implementations keep the local persistent store as the runtime source
/// of truth and use the folder only as an exchange layer.
public protocol LedgerFolderSyncing: Sendable {
    /// Imports and exports changes through an already-authorized folder.
    ///
    /// - Parameters:
    ///   - folderURL: The directory selected by the user. Permission management belongs to the caller.
    ///   - deviceID: An app-generated UUID that remains stable for this installation.
    /// - Returns: Counts for the completed exchange and its absolute completion time.
    func synchronize(folderURL: URL, deviceID: UUID) async throws -> LedgerFolderSyncReport
}

/// Summary of one successfully completed folder exchange.
public struct LedgerFolderSyncReport: Equatable, Sendable {
    public let importedRecordCount: Int
    public let exportedRecordCount: Int
    public let completedAt: Date

    public init(
        importedRecordCount: Int,
        exportedRecordCount: Int,
        completedAt: Date
    ) {
        self.importedRecordCount = importedRecordCount
        self.exportedRecordCount = exportedRecordCount
        self.completedAt = completedAt
    }
}

/// Platform-neutral states that a folder-sync UI can present.
public enum LedgerFolderSyncState: Equatable, Sendable {
    case notConfigured
    case idle(lastReport: LedgerFolderSyncReport?)
    case syncing
    case succeeded(LedgerFolderSyncReport)
    case failed(message: String)
}
