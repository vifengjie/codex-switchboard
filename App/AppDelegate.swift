import AppKit
import CodexQuotaCollectors
import CodexQuotaCore
import CodexQuotaStorage

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var refreshTask: Task<Void, Never>?
    private let notificationCoordinator = QuotaNotificationCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let snapshot = loadStartupSnapshot()
        let presenter = QuotaStatusPresenter()
        statusController = StatusItemController(
            snapshot: snapshot,
            presenter: presenter,
            refreshAction: { [weak self] in
                await self?.collectLatestSnapshot() ?? .storageFailed
            }
        )
        startCollectorPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        statusController = nil
    }

    private func loadStartupSnapshot() -> QuotaSnapshot {
        do {
            let store = SQLiteStore(databaseURL: try Self.defaultDatabaseURL())
            try store.migrate()

            let settingsRepository = SQLiteSettingsRepository(store: store)
            _ = try settingsRepository.ensureDefaultSettings()

            let snapshotRepository = SQLiteSnapshotRepository(store: store)
            if let snapshot = try snapshotRepository.latestSnapshot() {
                return snapshot
            }

            let initialSnapshot = QuotaSnapshot.unconfigured
            try snapshotRepository.save(initialSnapshot)
            return initialSnapshot
        } catch {
            NSLog("Codex Quota Manager startup storage failed: \(error)")
            return .storageFailed
        }
    }

    private func startCollectorPolling() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshStatusFromCollectors()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.refreshStatusFromCollectors()
            }
        }
    }

    private func refreshStatusFromCollectors() async {
        let snapshot = await collectLatestSnapshot()
        statusController?.update(snapshot: snapshot)
        await deliverNotificationIfNeeded(snapshot: snapshot)
    }

    private func collectLatestSnapshot() async -> QuotaSnapshot {
        do {
            return try await Task.detached(priority: .utility) {
                try await Self.runLocalCollectors()
            }.value
        } catch {
            NSLog("Codex Quota Manager collector refresh failed: \(error)")
            return loadStartupSnapshot()
        }
    }

    private nonisolated static func runLocalCollectors() async throws -> QuotaSnapshot {
        let store = SQLiteStore(databaseURL: try defaultDatabaseURL())
        try store.migrate()

        let settingsRepository = SQLiteSettingsRepository(store: store)
        _ = try settingsRepository.ensureDefaultSettings()

        let usageRepository = SQLiteUsageEventRepository(store: store)
        let snapshotRepository = SQLiteSnapshotRepository(store: store)
        let offsetRepository = SQLiteCollectorOffsetRepository(store: store)

        let codexRoot = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        let stateCollector = CodexStateSQLiteCollector(
            databaseURL: codexRoot.appending(path: "state_5.sqlite")
        )
        let threads = (try? stateCollector.listThreads()) ?? []
        let rolloutURLs = threads
            .map(\.rolloutPath)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        let metadataByRolloutPath = Dictionary(
            threads.map { (URL(fileURLWithPath: $0.rolloutPath).standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let jsonlCollector = LocalJSONLCollector(
            rootDirectory: codexRoot,
            rolloutPaths: rolloutURLs,
            threadMetadataByRolloutPath: metadataByRolloutPath,
            rateCardManager: .builtIn,
            usageEventRepository: usageRepository,
            snapshotRepository: snapshotRepository,
            offsetRepository: offsetRepository
        )
        _ = try await jsonlCollector.collect()

        if let snapshot = try snapshotRepository.latestSnapshot() {
            return snapshot
        }
        let initialSnapshot = QuotaSnapshot.unconfigured
        try snapshotRepository.save(initialSnapshot)
        return initialSnapshot
    }

    private nonisolated static func defaultDatabaseURL() throws -> URL {
        try CodexQuotaStoragePaths.defaultDatabaseURL()
    }

    private func deliverNotificationIfNeeded(snapshot: QuotaSnapshot) async {
        do {
            let store = SQLiteStore(databaseURL: try Self.defaultDatabaseURL())
            try store.migrate()
            await notificationCoordinator.deliverIfNeeded(snapshot: snapshot, store: store)
        } catch {
            NSLog("Codex Quota Manager notification storage failed: \(error)")
        }
    }
}
