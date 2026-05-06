import AppKit
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
        try await LocalQuotaRefreshService.collectLatestSnapshot()
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
