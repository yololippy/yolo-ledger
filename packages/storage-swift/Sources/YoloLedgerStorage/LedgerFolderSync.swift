import Foundation
import SwiftData
import YoloLedgerCore

public enum LedgerFolderSyncError: Error, Equatable, Sendable, LocalizedError {
    case invalidFolderURL
    case invalidSnapshot(file: String, reason: String)
    case unsupportedFormatVersion(file: String, found: Int)
    case unsupportedSchemaVersion(file: String, found: String)
    case fileCoordinationFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidFolderURL:
            "请选择一个可访问的本地文件夹或 iCloud Drive 文件夹。"
        case let .invalidSnapshot(file, reason):
            "同步文件 \(file) 无法读取：\(reason)"
        case let .unsupportedFormatVersion(file, found):
            "同步文件 \(file) 使用不受支持的格式版本 \(found)。"
        case let .unsupportedSchemaVersion(file, found):
            "同步文件 \(file) 使用不受支持的数据版本 \(found)。"
        case let .fileCoordinationFailed(message):
            "无法安全访问同步文件夹：\(message)"
        }
    }
}

struct LedgerFolderSnapshot: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let schemaVersion: String
    let deviceID: UUID
    let generatedAt: Date
    let books: [Book]
    let categories: [Category]
    let entries: [Entry]

    struct Book: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?
    }

    struct Category: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let kindRawValue: String
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?
    }

    struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let bookID: UUID
        let categoryID: UUID
        let kindRawValue: String
        let amountMinorUnits: Int64
        let occurredAt: Date
        let note: String
        let sourceRawValue: String
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?
    }
}

enum LedgerFolderSnapshotIO {
    static let rootDirectoryName = YoloLedgerProduct.syncDirectoryName
    static let devicesDirectoryName = "devices"

    static func readAll(from folderURL: URL) throws -> [LedgerFolderSnapshot] {
        let devicesURL = try prepareDirectories(in: folderURL)
        let fileURLs: [URL] = try coordinatedRead(at: devicesURL) { coordinatedURL in
            try FileManager.default.contentsOfDirectory(
                at: coordinatedURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        var snapshots: [LedgerFolderSnapshot] = []
        snapshots.reserveCapacity(fileURLs.count)
        for fileURL in fileURLs {
            let data: Data
            do {
                data = try coordinatedRead(at: fileURL) { coordinatedURL in
                    let values = try coordinatedURL.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                    )
                    guard values.isRegularFile == true, values.isSymbolicLink != true else {
                        throw LedgerFolderSyncError.invalidSnapshot(
                            file: fileURL.lastPathComponent,
                            reason: "不是普通 JSON 文件"
                        )
                    }
                    return try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                }
            } catch let error as LedgerFolderSyncError {
                throw error
            } catch {
                throw LedgerFolderSyncError.invalidSnapshot(
                    file: fileURL.lastPathComponent,
                    reason: error.localizedDescription
                )
            }
            let snapshot: LedgerFolderSnapshot
            do {
                snapshot = try decoder().decode(LedgerFolderSnapshot.self, from: data)
            } catch let error as LedgerFolderSyncError {
                throw error
            } catch {
                throw LedgerFolderSyncError.invalidSnapshot(
                    file: fileURL.lastPathComponent,
                    reason: error.localizedDescription
                )
            }
            try validate(snapshot, fileURL: fileURL)
            snapshots.append(snapshot)
        }
        if Set(snapshots.map(\.deviceID)).count != snapshots.count {
            throw LedgerFolderSyncError.invalidSnapshot(
                file: devicesURL.lastPathComponent,
                reason: "同一 deviceID 存在多个快照"
            )
        }
        return snapshots
    }

    static func write(_ snapshot: LedgerFolderSnapshot, to folderURL: URL) throws {
        try validate(snapshot, fileURL: nil)
        let devicesURL = try prepareDirectories(in: folderURL)
        let fileURL = devicesURL.appendingPathComponent(
            "\(snapshot.deviceID.uuidString.lowercased()).json",
            isDirectory: false
        )
        let data = try encoder().encode(snapshot)

        try coordinatedWrite(at: fileURL, options: .forReplacing) { coordinatedURL in
            let directoryURL = coordinatedURL.deletingLastPathComponent()
            let temporaryURL = directoryURL.appendingPathComponent(
                ".\(coordinatedURL.lastPathComponent).\(UUID().uuidString).tmp",
                isDirectory: false
            )
            do {
                try data.write(to: temporaryURL, options: [.withoutOverwriting])
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    _ = try FileManager.default.replaceItemAt(
                        coordinatedURL,
                        withItemAt: temporaryURL,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try FileManager.default.moveItem(at: temporaryURL, to: coordinatedURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    static func snapshotFileURL(in folderURL: URL, deviceID: UUID) -> URL {
        folderURL
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(devicesDirectoryName, isDirectory: true)
            .appendingPathComponent("\(deviceID.uuidString.lowercased()).json", isDirectory: false)
    }

    private static func prepareDirectories(in folderURL: URL) throws -> URL {
        guard folderURL.isFileURL else { throw LedgerFolderSyncError.invalidFolderURL }
        let values: URLResourceValues
        do {
            values = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
        } catch {
            throw LedgerFolderSyncError.invalidFolderURL
        }
        guard values.isDirectory == true else { throw LedgerFolderSyncError.invalidFolderURL }

        let devicesURL = folderURL
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(devicesDirectoryName, isDirectory: true)
        try coordinatedWrite(at: folderURL, options: .forMerging) { coordinatedFolderURL in
            let coordinatedDevicesURL = coordinatedFolderURL
                .appendingPathComponent(rootDirectoryName, isDirectory: true)
                .appendingPathComponent(devicesDirectoryName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: coordinatedDevicesURL,
                withIntermediateDirectories: true
            )
        }
        return devicesURL
    }

    private static func validate(_ snapshot: LedgerFolderSnapshot, fileURL: URL?) throws {
        let file = fileURL?.lastPathComponent
            ?? "\(snapshot.deviceID.uuidString.lowercased()).json"
        guard snapshot.formatVersion == LedgerFolderSnapshot.currentFormatVersion else {
            throw LedgerFolderSyncError.unsupportedFormatVersion(
                file: file,
                found: snapshot.formatVersion
            )
        }
        guard snapshot.schemaVersion == LocalLedgerStore.currentSchemaVersion else {
            throw LedgerFolderSyncError.unsupportedSchemaVersion(
                file: file,
                found: snapshot.schemaVersion
            )
        }
        if let fileURL {
            let filenameID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent)
            guard filenameID == snapshot.deviceID else {
                throw LedgerFolderSyncError.invalidSnapshot(
                    file: file,
                    reason: "文件名与 deviceID 不一致"
                )
            }
        }
        guard isFinite(snapshot.generatedAt) else {
            throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "generatedAt 无效")
        }
        try ensureUnique(snapshot.books.map(\.id), entity: "books", file: file)
        try ensureUnique(snapshot.categories.map(\.id), entity: "categories", file: file)
        try ensureUnique(snapshot.entries.map(\.id), entity: "entries", file: file)

        for record in snapshot.books {
            guard datesAreFinite(
                [record.createdAt, record.updatedAt],
                optional: record.deletedAt
            ) else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "账本时间无效")
            }
        }
        for record in snapshot.categories {
            guard LedgerEntryKind(rawValue: record.kindRawValue) != nil else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "分类收支类型无效")
            }
            guard datesAreFinite(
                [record.createdAt, record.updatedAt],
                optional: record.deletedAt
            ) else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "分类时间无效")
            }
        }

        let books = Dictionary(uniqueKeysWithValues: snapshot.books.map { ($0.id, $0) })
        let categories = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
        for record in snapshot.entries {
            guard let kind = LedgerEntryKind(rawValue: record.kindRawValue),
                  LedgerEntrySource(rawValue: record.sourceRawValue) != nil
            else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "账目类型或来源无效")
            }
            guard datesAreFinite(
                [
                    record.occurredAt,
                    record.createdAt,
                    record.updatedAt,
                ],
                optional: record.deletedAt
            ) else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "账目时间无效")
            }
            guard books[record.bookID] != nil,
                  let category = categories[record.categoryID]
            else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "账目引用不存在")
            }
            guard category.kindRawValue == kind.rawValue else {
                throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "账目与分类类型不一致")
            }
        }
    }

    private static func ensureUnique(_ ids: [UUID], entity: String, file: String) throws {
        guard Set(ids).count == ids.count else {
            throw LedgerFolderSyncError.invalidSnapshot(file: file, reason: "\(entity) 包含重复 UUID")
        }
    }

    private static func datesAreFinite(_ required: [Date], optional: Date?) -> Bool {
        required.allSatisfy(isFinite) && optional.map(isFinite) ?? true
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(preciseISO8601String(from: date))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = preciseISO8601Date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid precise ISO 8601 date"
                )
            }
            return date
        }
        return decoder
    }

    private static func preciseISO8601String(from date: Date) -> String {
        var wholeSeconds = floor(date.timeIntervalSince1970)
        var nanoseconds = Int(((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded())
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let base = formatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
        return "\(base).\(String(format: "%09d", nanoseconds))Z"
    }

    private static func preciseISO8601Date(from value: String) -> Date? {
        guard value.hasSuffix("Z"),
              let dot = value.lastIndex(of: ".")
        else { return nil }
        let fractionStart = value.index(after: dot)
        let fractionEnd = value.index(before: value.endIndex)
        let fraction = value[fractionStart..<fractionEnd]
        guard (1...9).contains(fraction.count),
              fraction.allSatisfy(\.isNumber),
              let fractionalSeconds = Double("0.\(fraction)")
        else { return nil }
        let wholeSecondsString = String(value[..<dot]) + "Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: wholeSecondsString)?.addingTimeInterval(fractionalSeconds)
    }

    private static func coordinatedRead<Value>(
        at url: URL,
        _ body: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError {
            throw LedgerFolderSyncError.fileCoordinationFailed(message: coordinationError.localizedDescription)
        }
        guard let result else {
            throw LedgerFolderSyncError.fileCoordinationFailed(message: "文件协调没有返回结果")
        }
        return try result.get()
    }

    private static func coordinatedWrite(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: (URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try body(coordinatedURL)
            } catch {
                operationError = error
            }
        }
        if let coordinationError {
            throw LedgerFolderSyncError.fileCoordinationFailed(message: coordinationError.localizedDescription)
        }
        if let operationError { throw operationError }
    }
}

struct LedgerFolderMergeResult: Sendable {
    let importedRecordCount: Int
    let snapshot: LedgerFolderSnapshot
}

protocol LedgerFolderVersionedRecord: Codable, Equatable, Sendable {
    var id: UUID { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

extension LedgerFolderSnapshot.Book: LedgerFolderVersionedRecord {
    init(_ record: LedgerSchemaV1.BookRecord) {
        self.init(
            id: record.id,
            name: record.name,
            sortOrder: record.sortOrder,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }

    func apply(to record: LedgerSchemaV1.BookRecord) {
        record.name = name
        record.sortOrder = sortOrder
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.deletedAt = deletedAt
    }
}

extension LedgerFolderSnapshot.Category: LedgerFolderVersionedRecord {
    init(_ record: LedgerSchemaV1.CategoryRecord) {
        self.init(
            id: record.id,
            name: record.name,
            kindRawValue: record.kindRawValue,
            sortOrder: record.sortOrder,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }

    func apply(to record: LedgerSchemaV1.CategoryRecord) {
        record.name = name
        record.kindRawValue = kindRawValue
        record.sortOrder = sortOrder
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.deletedAt = deletedAt
    }
}

extension LedgerFolderSnapshot.Entry: LedgerFolderVersionedRecord {
    init(_ record: LedgerSchemaV1.EntryRecord) {
        self.init(
            id: record.id,
            bookID: record.bookID,
            categoryID: record.categoryID,
            kindRawValue: record.kindRawValue,
            amountMinorUnits: record.amountMinorUnits,
            occurredAt: record.occurredAt,
            note: record.note,
            sourceRawValue: record.sourceRawValue,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }

    func apply(to record: LedgerSchemaV1.EntryRecord) {
        record.bookID = bookID
        record.categoryID = categoryID
        record.kindRawValue = kindRawValue
        record.amountMinorUnits = amountMinorUnits
        record.occurredAt = occurredAt
        record.note = note
        record.sourceRawValue = sourceRawValue
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.deletedAt = deletedAt
    }
}

struct LedgerFolderCandidate<Record: LedgerFolderVersionedRecord>: Sendable {
    let record: Record
    let sourceDeviceID: UUID
}
