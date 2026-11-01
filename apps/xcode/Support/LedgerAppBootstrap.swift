import Foundation
import Observation
import SwiftUI
#if os(iOS)
import BackgroundTasks
import UserNotifications
#endif
import YoloLedgerCore
import YoloLedgerStorage
import YoloLedgerUI

@MainActor
@Observable
final class LedgerAppBootstrap {
    private(set) var repository: (any LedgerRepository)?
    private(set) var folderSyncCoordinator: LedgerFolderSyncCoordinator?
    let folderSyncController = LedgerFolderSyncController()
    let meowImportController = LedgerMeowImportController()
    private(set) var scheduledEntryController: LedgerScheduledEntryController?
    #if os(iOS)
    private(set) var scheduledEntryCoordinator: LedgerScheduledEntryCoordinator?
    #endif
    private(set) var failure: String?
    private(set) var isOpening = false
    #if DEBUG
    private var failsOnce = ProcessInfo.processInfo.arguments.contains("--ui-test-fail-open-once")
    #endif

    func open(synchronizeAfterOpening: Bool = true) async {
        guard repository == nil, !isOpening else { return }
        isOpening = true
        failure = nil
        defer { isOpening = false }
        do {
            let storeURL = try storeURL()
            #if DEBUG
            if failsOnce {
                failsOnce = false
                throw LaunchError.injectedFailure
            }
            #endif
            let repository = try await Task.detached(priority: .userInitiated) {
                try SwiftDataLedgerRepository(storeURL: storeURL, syncMode: .local)
            }.value
            self.repository = repository
            let importHandler = repository.makeMeowImportHandler()
            meowImportController.installImportAction { [folderSyncController] plans in
                let report = try await importHandler(plans)
                folderSyncController.localDataDidChange()
                return LedgerMeowImportResult(
                    importedRecordCount: report.importedEntryCount,
                    skippedDuplicateRecordCount: report.skippedDuplicateCount,
                    createdBookCount: report.createdBookCount,
                    createdCategoryCount: report.createdCategoryCount,
                    importedExpenseCount: report.importedExpenseCount,
                    importedIncomeCount: report.importedIncomeCount,
                    importedExpenseTotalText: Self.currencyText(report.importedExpenseTotalMinorUnits),
                    importedIncomeTotalText: Self.currencyText(report.importedIncomeTotalMinorUnits),
                    backupName: report.backupURL.lastPathComponent
                )
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-meow-import") {
                meowImportController.installDocumentSelectionAction {
                    Self.meowImportUITestDocuments
                }
            }
            #endif
            #if os(iOS)
            let scheduledRepository: any LedgerScheduledEntryRepository = repository
            let controller = LedgerScheduledEntryController(repository: scheduledRepository)
            let coordinator = LedgerScheduledEntryCoordinator(
                repository: scheduledRepository,
                controller: controller,
                generatedEntriesAction: { [folderSyncController] in
                    folderSyncController.localDataDidChange()
                },
                suppressNotifications: ProcessInfo.processInfo.arguments.contains("--ui-test-scheduled-entries")
            )
            controller.installActions(
                enabledRuleSaved: { [weak coordinator] in
                    await coordinator?.enabledRuleWasSaved()
                },
                rulesChanged: { [weak coordinator] in
                    await coordinator?.rulesDidChange()
                }
            )
            scheduledEntryController = controller
            scheduledEntryCoordinator = coordinator
            coordinator.start()
            #endif
            if isUITestStore {
                folderSyncController.update(folderName: nil, state: .notConfigured)
            } else {
                folderSyncCoordinator = LedgerFolderSyncCoordinator(
                    synchronizer: repository,
                    controller: folderSyncController
                )
                folderSyncCoordinator?.start(synchronizeImmediately: synchronizeAfterOpening)
            }
        } catch {
            let detail = (error as? any LocalizedError)?.errorDescription ?? "请检查本机存储空间或稍后重试。"
            failure = "本地账库无法打开。\(detail)"
        }
    }

    private func storeURL() throws -> URL {
        let standard = try SwiftDataLedgerRepository.defaultStoreURL()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--ui-test-store") {
            guard args.indices.contains(index + 1), let id = UUID(uuidString: args[index + 1]) else {
                throw LaunchError.invalidTestStore
            }
            let url = standard.deletingLastPathComponent()
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("ledger.store", isDirectory: false)
            return url
        }
        #endif
        return standard
    }

    private var isUITestStore: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-test-store")
        #else
        false
        #endif
    }

    private static func currencyText(_ minorUnits: Decimal) -> String {
        var majorUnits = minorUnits
        majorUnits /= 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return "¥" + (formatter.string(from: NSDecimalNumber(decimal: majorUnits)) ?? "0.00")
    }

    #if DEBUG
    private static var meowImportUITestDocuments: [LedgerMeowImportDocument] {
        let header = "分类,时间,金额,账户,账本,货币,备注"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let expense = "餐饮,\(timestamp),-12.50,现金,日常,CNY,脱敏午餐"
        let income = "工资,\(timestamp),+1000.00,银行卡,日常,CNY,脱敏工资"
        return [
            LedgerMeowImportDocument(
                name: "脱敏样本一.csv",
                data: Data("\(header)\n\(expense)".utf8)
            ),
            LedgerMeowImportDocument(
                name: "脱敏样本二.csv",
                data: Data("\(header)\n\(income)\n\(expense)".utf8)
            ),
        ]
    }
    #endif
}

private enum LaunchError: LocalizedError {
    case injectedFailure, invalidTestStore
    var errorDescription: String? {
        switch self {
        case .injectedFailure: "测试启动失败，请点击重试。"
        case .invalidTestStore: "测试账库标识无效。"
        }
    }
}

@MainActor
struct LedgerAppContent: View {
    let bootstrap: LedgerAppBootstrap
    @Binding private var pendingScreenshotProposal: LedgerScreenshotProposal?
    @State private var showsOpeningMessage = false

    init(
        bootstrap: LedgerAppBootstrap,
        pendingScreenshotProposal: Binding<LedgerScreenshotProposal?> = .constant(nil)
    ) {
        self.bootstrap = bootstrap
        _pendingScreenshotProposal = pendingScreenshotProposal
    }

    var body: some View {
        ZStack {
            if let repository = bootstrap.repository {
                YoloLedgerRootView(
                    repository: repository,
                    pendingScreenshotProposal: $pendingScreenshotProposal,
                    folderSync: bootstrap.folderSyncController,
                    meowImport: bootstrap.meowImportController,
                    scheduledEntries: bootstrap.scheduledEntryController
                )
            } else if let failure = bootstrap.failure {
                ContentUnavailableView {
                    Label("无法打开本地账库", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(failure).accessibilityIdentifier("startup.error")
                } actions: {
                    Button("重试") { Task { await bootstrap.open() } }
                        .accessibilityIdentifier("startup.retry")
                }
            } else if showsOpeningMessage {
                ProgressView("正在打开本地账库")
            }
        }
        .ledgerTheme(.pastel)
        .task {
            await bootstrap.open()
        }
        .task(id: bootstrap.isOpening) {
            guard bootstrap.isOpening else {
                showsOpeningMessage = false
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, bootstrap.isOpening, bootstrap.failure == nil else { return }
            showsOpeningMessage = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                bootstrap.folderSyncCoordinator?.becameActive()
                #if os(iOS)
                bootstrap.scheduledEntryCoordinator?.becameActive()
                #endif
            }
        }
    }
    @Environment(\.scenePhase) private var scenePhase
}

@MainActor
final class LedgerFolderSyncCoordinator {
    private let synchronizer: any LedgerFolderSyncing
    private let controller: LedgerFolderSyncController
    private let defaults: UserDefaults
    private let deviceID: UUID
    private var syncTask: Task<Bool, Never>?
    private var debounceTask: Task<Void, Never>?
    private var initialSyncTask: Task<Void, Never>?
    private var needsAnotherSync = false
    private var hasStarted = false

    init(
        synchronizer: any LedgerFolderSyncing,
        controller: LedgerFolderSyncController,
        defaults: UserDefaults = .standard
    ) {
        self.synchronizer = synchronizer
        self.controller = controller
        self.defaults = defaults
        self.deviceID = Self.loadOrCreateDeviceID(defaults: defaults)
        controller.installActions(
            selectFolder: { [weak self] url in await self?.selectFolder(url) },
            synchronize: { [weak self] in _ = await self?.synchronizeNow() },
            stop: { [weak self] in self?.stopUsingFolder() },
            localMutation: { [weak self] in self?.localDataDidChange() }
        )
    }

    func start(synchronizeImmediately: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        restoreConfiguration()
        if synchronizeImmediately, controller.isConfigured {
            initialSyncTask = Task { [weak self] in
                // Prioritize the bounded local query so launch is never queued behind file exchange.
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled, let self else { return }
                self.initialSyncTask = nil
                _ = await self.synchronizeNow()
            }
        }
    }

    func becameActive() {
        guard hasStarted, controller.isConfigured, initialSyncTask == nil else { return }
        Task { _ = await synchronizeNow() }
    }

    func localDataDidChange() {
        guard controller.isConfigured else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            _ = await self?.synchronizeNow()
        }
    }

    @discardableResult
    func synchronizeNow() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        if let syncTask {
            needsAnotherSync = true
            return await syncTask.value
        }
        guard defaults.data(forKey: FolderSyncPreferences.bookmarkKey) != nil else {
            controller.update(folderName: nil, state: .notConfigured)
            return false
        }

        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performSync()
        }
        syncTask = task
        let succeeded = await task.value
        syncTask = nil

        if needsAnotherSync {
            needsAnotherSync = false
            Task { [weak self] in _ = await self?.synchronizeNow() }
        }
        return succeeded
    }

    func cancelCurrentSync() {
        syncTask?.cancel()
    }

    private func selectFolder(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        guard accessed else {
            controller.update(folderName: url.lastPathComponent, state: .failed(message: "没有所选文件夹的访问权限。"))
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try Self.createBookmark(for: url)
            defaults.set(bookmark, forKey: FolderSyncPreferences.bookmarkKey)
            defaults.set(url.lastPathComponent, forKey: FolderSyncPreferences.folderNameKey)
            clearLastReport()
            controller.update(folderName: url.lastPathComponent, state: .idle(lastReport: nil))
            #if os(iOS)
            FolderSyncBackgroundTasks.schedule()
            #endif
            _ = await synchronizeNow()
        } catch {
            controller.update(folderName: url.lastPathComponent, state: .failed(message: Self.message(for: error)))
        }
    }

    private func stopUsingFolder() {
        initialSyncTask?.cancel()
        debounceTask?.cancel()
        syncTask?.cancel()
        initialSyncTask = nil
        debounceTask = nil
        syncTask = nil
        needsAnotherSync = false
        defaults.removeObject(forKey: FolderSyncPreferences.bookmarkKey)
        defaults.removeObject(forKey: FolderSyncPreferences.folderNameKey)
        clearLastReport()
        controller.update(folderName: nil, state: .notConfigured)
        // A pending refresh may also belong to scheduled entries; let it run once instead of cancelling it.
    }

    private func restoreConfiguration() {
        guard let bookmark = defaults.data(forKey: FolderSyncPreferences.bookmarkKey) else {
            controller.update(folderName: nil, state: .notConfigured)
            return
        }
        do {
            var isStale = false
            let url = try Self.resolveBookmark(bookmark, isStale: &isStale)
            if isStale {
                let accessed = url.startAccessingSecurityScopedResource()
                guard accessed else { throw FolderSyncAccessError.permissionDenied }
                defer { url.stopAccessingSecurityScopedResource() }
                defaults.set(try Self.createBookmark(for: url), forKey: FolderSyncPreferences.bookmarkKey)
            }
            let name = url.lastPathComponent
            defaults.set(name, forKey: FolderSyncPreferences.folderNameKey)
            controller.update(folderName: name, state: .idle(lastReport: loadLastReport()))
            #if os(iOS)
            FolderSyncBackgroundTasks.schedule()
            #endif
        } catch {
            let name = defaults.string(forKey: FolderSyncPreferences.folderNameKey)
            controller.update(folderName: name, state: .failed(message: "同步文件夹权限已失效，请更换文件夹。"))
        }
    }

    private func performSync() async -> Bool {
        guard let bookmark = defaults.data(forKey: FolderSyncPreferences.bookmarkKey) else { return false }
        let fallbackName = defaults.string(forKey: FolderSyncPreferences.folderNameKey)
        controller.update(folderName: fallbackName, state: .syncing)
        do {
            var isStale = false
            let url = try Self.resolveBookmark(bookmark, isStale: &isStale)
            let accessed = url.startAccessingSecurityScopedResource()
            guard accessed else { throw FolderSyncAccessError.permissionDenied }
            defer { url.stopAccessingSecurityScopedResource() }

            if isStale {
                defaults.set(try Self.createBookmark(for: url), forKey: FolderSyncPreferences.bookmarkKey)
            }
            try Task.checkCancellation()
            let report = try await synchronizer.synchronize(folderURL: url, deviceID: deviceID)
            try Task.checkCancellation()
            saveLastReport(report)
            controller.reportSuccessfulSync(folderName: url.lastPathComponent, report: report)
            #if os(iOS)
            FolderSyncBackgroundTasks.schedule()
            #endif
            return true
        } catch is CancellationError {
            controller.update(folderName: fallbackName, state: .idle(lastReport: loadLastReport()))
            return false
        } catch {
            controller.update(folderName: fallbackName, state: .failed(message: Self.message(for: error)))
            #if os(iOS)
            FolderSyncBackgroundTasks.schedule()
            #endif
            return false
        }
    }

    private func saveLastReport(_ report: LedgerFolderSyncReport) {
        defaults.set(report.completedAt.timeIntervalSince1970, forKey: FolderSyncPreferences.completedAtKey)
        defaults.set(report.importedRecordCount, forKey: FolderSyncPreferences.importedCountKey)
        defaults.set(report.exportedRecordCount, forKey: FolderSyncPreferences.exportedCountKey)
    }

    private func loadLastReport() -> LedgerFolderSyncReport? {
        guard defaults.object(forKey: FolderSyncPreferences.completedAtKey) != nil else { return nil }
        return LedgerFolderSyncReport(
            importedRecordCount: defaults.integer(forKey: FolderSyncPreferences.importedCountKey),
            exportedRecordCount: defaults.integer(forKey: FolderSyncPreferences.exportedCountKey),
            completedAt: Date(timeIntervalSince1970: defaults.double(forKey: FolderSyncPreferences.completedAtKey))
        )
    }

    private func clearLastReport() {
        defaults.removeObject(forKey: FolderSyncPreferences.completedAtKey)
        defaults.removeObject(forKey: FolderSyncPreferences.importedCountKey)
        defaults.removeObject(forKey: FolderSyncPreferences.exportedCountKey)
    }

    private static func loadOrCreateDeviceID(defaults: UserDefaults) -> UUID {
        if let value = defaults.string(forKey: FolderSyncPreferences.deviceIDKey), let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: FolderSyncPreferences.deviceIDKey)
        return id
    }

    private static func createBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static func resolveBookmark(_ data: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
        try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "文件夹同步失败，请稍后重试。"
    }
}

private enum FolderSyncPreferences {
    static let bookmarkKey = "folder-sync.bookmark-v1"
    static let folderNameKey = "folder-sync.folder-name-v1"
    static let deviceIDKey = "folder-sync.device-id-v1"
    static let completedAtKey = "folder-sync.completed-at-v1"
    static let importedCountKey = "folder-sync.imported-count-v1"
    static let exportedCountKey = "folder-sync.exported-count-v1"
}

private enum FolderSyncAccessError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "无法访问同步文件夹，权限可能已被撤销。"
    }
}

#if os(iOS)
@MainActor
enum FolderSyncBackgroundTasks {
    static let identifier: String = {
        guard let identifiers = Bundle.main.object(
            forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers"
        ) as? [String], let identifier = identifiers.first else {
            preconditionFailure("Missing BGTaskSchedulerPermittedIdentifiers")
        }
        return identifier
    }()
    private static weak var bootstrap: LedgerAppBootstrap?
    private static var isRegistered = false

    static func register(bootstrap: LedgerAppBootstrap) {
        self.bootstrap = bootstrap
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                guard let currentBootstrap = FolderSyncBackgroundTasks.bootstrap else {
                    refreshTask.setTaskCompleted(success: false)
                    return
                }
                await currentBootstrap.open(synchronizeAfterOpening: false)
                let scheduledSucceeded = if let coordinator = currentBootstrap.scheduledEntryCoordinator {
                    await coordinator.processDueEntries()
                } else {
                    true
                }
                let syncSucceeded = if currentBootstrap.folderSyncController.isConfigured,
                                       let coordinator = currentBootstrap.folderSyncCoordinator {
                    await coordinator.synchronizeNow()
                } else {
                    true
                }
                refreshTask.setTaskCompleted(success: syncSucceeded && scheduledSucceeded)
            }
            refreshTask.expirationHandler = {
                work.cancel()
                Task { @MainActor in
                    FolderSyncBackgroundTasks.bootstrap?.folderSyncCoordinator?.cancelCurrentSync()
                    FolderSyncBackgroundTasks.bootstrap?.scheduledEntryCoordinator?.cancelCurrentProcessing()
                }
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

}

@MainActor
final class LedgerScheduledEntryCoordinator {
    typealias GeneratedEntriesAction = @MainActor @Sendable () -> Void

    private static let notificationIdentifier = "scheduled-entry.next-due"
    private static let permissionRequestedKey = "scheduled-entry.notification-permission-requested-v1"

    private let repository: any LedgerScheduledEntryRepository
    private let controller: LedgerScheduledEntryController
    private let generatedEntriesAction: GeneratedEntriesAction
    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let suppressNotifications: Bool
    private var processingTask: Task<Bool, Never>?

    init(
        repository: any LedgerScheduledEntryRepository,
        controller: LedgerScheduledEntryController,
        generatedEntriesAction: @escaping GeneratedEntriesAction = {},
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        suppressNotifications: Bool = false
    ) {
        self.repository = repository
        self.controller = controller
        self.generatedEntriesAction = generatedEntriesAction
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.suppressNotifications = suppressNotifications
    }

    func start() {
        Task { [weak self] in _ = await self?.processDueEntries() }
    }

    func becameActive() {
        Task { [weak self] in _ = await self?.processDueEntries() }
    }

    func enabledRuleWasSaved() async {
        await requestNotificationPermissionIfNeeded()
        _ = await processDueEntries()
    }

    func rulesDidChange() async {
        await rescheduleNotification()
        await scheduleBackgroundRefreshIfNeeded()
    }

    @discardableResult
    func processDueEntries() async -> Bool {
        if let processingTask { return await processingTask.value }
        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performProcessing()
        }
        processingTask = task
        let succeeded = await task.value
        processingTask = nil
        return succeeded
    }

    func cancelCurrentProcessing() {
        processingTask?.cancel()
    }

    private func performProcessing() async -> Bool {
        do {
            let now = Date()
            let calendar = Self.localGregorianCalendar(timeZone: .current)
            let result = try await repository.processDueScheduledEntries(
                now: now,
                calendar: calendar,
                timeZone: .current
            )
            try Task.checkCancellation()
            LedgerScheduledEntryController.performGeneratedEntriesAction(
                generatedCount: result.generatedCount
            ) {
                generatedEntriesAction()
            }
            await controller.reportSuccessfulProcessing(generatedCount: result.generatedCount)
            await rescheduleNotification(after: now)
            await scheduleBackgroundRefreshIfNeeded(after: now)
            return true
        } catch is CancellationError {
            return false
        } catch {
            FolderSyncBackgroundTasks.schedule()
            return false
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        guard !suppressNotifications,
              !defaults.bool(forKey: Self.permissionRequestedKey)
        else { return }
        defaults.set(true, forKey: Self.permissionRequestedKey)
        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
    }

    private func rescheduleNotification(after now: Date = Date()) async {
        guard !suppressNotifications else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        do {
            let calendar = Self.localGregorianCalendar(timeZone: .current)
            guard let nextDate = try await repository.nextScheduledEntryDate(
                after: now,
                calendar: calendar,
                timeZone: .current
            ) else { return }
            let content = UNMutableNotificationContent()
            content.title = "定时记账提醒"
            content.body = "有一笔定时账目已到期，打开\(YoloLedgerProduct.displayName)后会自动补记。"
            content.sound = .default
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
            components.calendar = calendar
            components.timeZone = .current
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await notificationCenter.add(UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: trigger
            ))
        } catch {
            // Notifications are best effort and never block scheduled-entry persistence.
        }
    }

    private func scheduleBackgroundRefreshIfNeeded(after now: Date = Date()) async {
        do {
            let calendar = Self.localGregorianCalendar(timeZone: .current)
            if try await repository.nextScheduledEntryDate(
                after: now,
                calendar: calendar,
                timeZone: .current
            ) != nil {
                FolderSyncBackgroundTasks.schedule()
            }
        } catch {
            // A failed query is retried the next time the App becomes active.
        }
    }

    private static func localGregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

#endif
