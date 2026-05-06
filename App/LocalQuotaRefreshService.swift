import CodexQuotaCollectors
import CodexQuotaCore
import CodexQuotaStorage
import Foundation

enum LocalQuotaRefreshService {
    static func collectLatestSnapshot(accountAlias: String? = nil) async throws -> QuotaSnapshot {
        let store = SQLiteStore(databaseURL: try CodexQuotaStoragePaths.defaultDatabaseURL())
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
            accountAlias: accountAlias ?? "本机 Codex",
            rateCardManager: .builtIn,
            usageEventRepository: usageRepository,
            snapshotRepository: snapshotRepository,
            offsetRepository: offsetRepository
        )
        _ = try await jsonlCollector.collect()

        if let accountAlias, let snapshot = try snapshotRepository.latestSnapshot(accountAlias: accountAlias) {
            return snapshot
        }
        if let snapshot = try snapshotRepository.latestSnapshot() {
            return snapshot
        }
        let initialSnapshot = QuotaSnapshot.unconfigured
        try snapshotRepository.save(initialSnapshot)
        return initialSnapshot
    }
}
