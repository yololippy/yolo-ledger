import CloudKit
import CoreData
import Foundation
import YoloLedgerCore

final class CloudSyncMonitor: @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let cloudContainer: CKContainer?
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var state: LedgerSyncState

    init(syncMode: LedgerSyncMode, notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        switch syncMode {
        case .local:
            cloudContainer = nil
            state = .localOnly
        case let .iCloudPrivate(containerIdentifier):
            cloudContainer = CKContainer(identifier: containerIdentifier)
            state = .checking
        }

        if cloudContainer != nil {
            observers.append(notificationCenter.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handle(notification)
            })
            observers.append(notificationCenter.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.refreshAccountStatus()
            })
            refreshAccountStatus()
        }
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
        finishStreams()
    }

    func updates() -> AsyncStream<Void> {
        guard cloudContainer != nil else {
            return AsyncStream { continuation in continuation.finish() }
        }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.removeContinuation(id) }
        }
    }

    func currentState() -> LedgerSyncState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func refreshAccountStatus() {
        guard let cloudContainer else { return }
        Task { [weak self] in
            do {
                let status = try await cloudContainer.accountStatus()
                let nextState: LedgerSyncState = switch status {
                case .available: .available(lastSuccessfulSync: nil)
                case .noAccount: .unavailable(reason: "设备未登录 Apple Account。")
                case .restricted: .unavailable(reason: "系统限制了此设备的 iCloud 访问。")
                case .temporarilyUnavailable: .unavailable(reason: "iCloud 暂时不可用，请稍后重试。")
                case .couldNotDetermine: .unavailable(reason: "暂时无法确认 iCloud 账户状态。")
                @unknown default: .unavailable(reason: "当前 iCloud 账户状态不可用。")
                }
                self?.setState(nextState)
            } catch {
                self?.setState(.error(message: "检查 iCloud 状态失败：\(error.localizedDescription)"))
            }
        }
    }

    private func handle(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else { return }

        guard event.endDate != nil else {
            setState(.syncing)
            return
        }

        if event.succeeded {
            setState(.available(lastSuccessfulSync: event.endDate))
        } else {
            let message = event.error?.localizedDescription ?? "iCloud 同步未完成，请稍后重试。"
            setState(.error(message: message))
        }
    }

    private func setState(_ newState: LedgerSyncState) {
        lock.lock()
        state = newState
        let values = Array(continuations.values)
        lock.unlock()
        for continuation in values { continuation.yield() }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }

    private func finishStreams() {
        lock.lock()
        let values = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in values { continuation.finish() }
    }
}
