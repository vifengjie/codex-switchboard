import AppKit
import CodexQuotaExport
import CodexQuotaCore
import CodexQuotaStorage
import CodexQuotaSwitch
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ManagementViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var latestSnapshot: QuotaSnapshot?
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var usageEvents: [UsageEvent] = []
    @Published var usageFilter: UsageEventFilter = .default
    @Published var auditFilter: AuditEventFilter = .default
    @Published private(set) var statusMessage = "就绪"
    @Published var pendingSwitchPreflight: SwitchPreflight?
    @Published var activeSwitchSession: SwitchSession?
    @Published var pendingCleanupOptions = CleanupOptions()
    @Published var showingCleanupSheet = false

    private let store: SQLiteStore
    private let usageEventRepository: SQLiteUsageEventRepository
    private let auditRepository: SQLiteAuditRepository
    private let accountRepository: SQLiteAccountRepository
    private let settingsRepository: SQLiteSettingsRepository
    private let snapshotRepository: SQLiteSnapshotRepository
    private let switchEventRepository: SQLiteSwitchEventRepository
    private let maintenanceRepository: SQLiteMaintenanceRepository
    private let diagnosticsRepository: SQLiteDiagnosticsRepository
    private let keychainStore = KeychainStore()
    private let exporter = UsageEventExporter()
    private let diagnosticsExporter = DiagnosticsExporter()
    private let accountManager: AccountManager
    private let switchCoordinator: SwitchCoordinator
    private var activeSwitchTask: Task<Void, Never>?

    init() {
        let resolvedStore: SQLiteStore
        let initialStatus: String

        do {
            let store = SQLiteStore(databaseURL: try CodexQuotaStoragePaths.defaultDatabaseURL())
            try store.migrate()
            resolvedStore = store
            initialStatus = "就绪"
        } catch {
            resolvedStore = SQLiteStore(
                databaseURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("codex-quota-manager-fallback.sqlite")
            )
            initialStatus = "存储初始化失败：\(error.localizedDescription)"
        }

        let resolvedUsageEventRepository = SQLiteUsageEventRepository(store: resolvedStore)
        let resolvedAuditRepository = SQLiteAuditRepository(store: resolvedStore)
        let resolvedAccountRepository = SQLiteAccountRepository(store: resolvedStore)
        let resolvedSettingsRepository = SQLiteSettingsRepository(store: resolvedStore)
        let resolvedSnapshotRepository = SQLiteSnapshotRepository(store: resolvedStore)
        let resolvedSwitchEventRepository = SQLiteSwitchEventRepository(store: resolvedStore)
        let resolvedMaintenanceRepository = SQLiteMaintenanceRepository(store: resolvedStore)
        let resolvedDiagnosticsRepository = SQLiteDiagnosticsRepository(store: resolvedStore)

        self.store = resolvedStore
        self.usageEventRepository = resolvedUsageEventRepository
        self.auditRepository = resolvedAuditRepository
        self.accountRepository = resolvedAccountRepository
        self.settingsRepository = resolvedSettingsRepository
        self.snapshotRepository = resolvedSnapshotRepository
        self.switchEventRepository = resolvedSwitchEventRepository
        self.maintenanceRepository = resolvedMaintenanceRepository
        self.diagnosticsRepository = resolvedDiagnosticsRepository
        self.accountManager = AccountManager(
            accountRepository: resolvedAccountRepository,
            auditRepository: resolvedAuditRepository
        )
        self.switchCoordinator = SwitchCoordinator(
            accountRepository: resolvedAccountRepository,
            snapshotRepository: resolvedSnapshotRepository,
            switchEventRepository: resolvedSwitchEventRepository,
            auditRepository: resolvedAuditRepository,
            provider: CodexCLISwitchProvider(
                openScript: { scriptURL in
                    await MainActor.run {
                        NSWorkspace.shared.open(scriptURL)
                    }
                }
            )
        )
        self.statusMessage = initialStatus

        reload()
    }

    func reload(statusMessage: String = "已刷新") {
        do {
            settings = try settingsRepository.ensureDefaultSettings()
            accounts = try accountRepository.listAccounts()
            latestSnapshot = try snapshotRepository.latestSnapshot()
            auditEvents = try auditRepository.query(auditFilter)
            usageEvents = try usageEventRepository.query(usageFilter)
            self.statusMessage = statusMessage
        } catch {
            self.statusMessage = "刷新失败：\(error.localizedDescription)"
        }
    }

    func applyUsageFilter(_ filter: UsageEventFilter) {
        usageFilter = filter
        reload(statusMessage: "明细筛选已更新")
    }

    func resetUsageFilter() {
        usageFilter = .default
        reload(statusMessage: "明细筛选已重置")
    }

    func applyAuditFilter(_ filter: AuditEventFilter) {
        auditFilter = filter
        reload(statusMessage: "审计筛选已更新")
    }

    func resetAuditFilter() {
        auditFilter = .default
        reload(statusMessage: "审计筛选已重置")
    }

    func addLocalAccount() {
        let nextIndex = accounts.count + 1
        saveAccount(
            Account(
                alias: "本地账号 \(nextIndex)",
                provider: .chatgpt,
                enabled: true,
                priority: max(0, 100 - nextIndex)
            )
        )
    }

    func saveAccount(_ account: Account) {
        do {
            let existing = try accountRepository.account(id: account.id)
            if existing == nil {
                try accountRepository.upsert(account)
                try auditRepository.record(
                    AuditEvent(
                        eventType: .accountCreate,
                        objectType: "account",
                        objectID: account.id.uuidString,
                        result: .success,
                        message: "添加账号：\(account.alias)"
                    )
                )
                reload(statusMessage: "账号已添加并写入审计")
            } else {
                _ = try accountManager.saveAccount(account, message: "更新账号：\(account.alias)")
                reload(statusMessage: "账号已更新并写入审计")
            }
        } catch {
            statusMessage = "保存账号失败：\(error.localizedDescription)"
        }
    }

    func toggleEnabled(account: Account) {
        do {
            _ = try accountManager.setEnabled(accountID: account.id, enabled: !account.enabled)
            reload(statusMessage: "账号状态已更新并写入审计")
        } catch {
            statusMessage = "更新账号失败：\(error.localizedDescription)"
        }
    }

    func delete(account: Account) {
        do {
            try accountManager.deleteAccount(accountID: account.id)
            reload(statusMessage: "账号已删除并写入审计")
        } catch {
            statusMessage = "删除账号失败：\(error.localizedDescription)"
        }
    }

    func saveSettings(_ updatedSettings: AppSettings) {
        do {
            try settingsRepository.save(updatedSettings)
            try auditRepository.record(
                AuditEvent(
                    eventType: .settingsUpdate,
                    objectType: "settings",
                    objectID: "default",
                    result: .success,
                    message: "更新策略：5H \(Int(updatedSettings.fiveHourRiskThresholdPercent))%，1W \(Int(updatedSettings.weeklyCriticalThresholdPercent))%"
                )
            )
            reload(statusMessage: "策略已保存并写入审计")
        } catch {
            statusMessage = "保存策略失败：\(error.localizedDescription)"
        }
    }

    func prepareSwitch(account: Account) {
        do {
            pendingSwitchPreflight = try switchCoordinator.preflight(targetAccountID: account.id)
            statusMessage = "切换前检查通过，请确认"
        } catch {
            pendingSwitchPreflight = nil
            statusMessage = "切换前检查失败：\(switchErrorMessage(error))"
        }
    }

    func cancelPreparedSwitch() {
        pendingSwitchPreflight = nil
        statusMessage = "切换已取消"
    }

    func launchPreparedSwitch() {
        guard let preflight = pendingSwitchPreflight else {
            return
        }
        statusMessage = "正在打开官方登录 / 账号选择流程..."
        Task {
            do {
                let session = try await switchCoordinator.launch(preflight)
                pendingSwitchPreflight = nil
                activeSwitchSession = session
                statusMessage = "Codex 登录流程已启动，正在等待登录完成..."
                beginAwaitingActiveSwitch(session)
            } catch {
                pendingSwitchPreflight = nil
                reload(statusMessage: "启动切换失败：\(error.localizedDescription)")
            }
        }
    }

    func cancelActiveSwitchSession() {
        activeSwitchTask?.cancel()
        activeSwitchTask = nil
        activeSwitchSession = nil
        statusMessage = "切换等待已取消"
    }

    func exportUsageEvents(format: UsageEventExportFormat) {
        do {
            let data = try exporter.export(events: usageEvents, format: format)
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = defaultExportFilename(format: format)
            savePanel.allowedContentTypes = contentTypes(for: format)
            guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
                statusMessage = "已取消导出"
                return
            }
            try data.write(to: destinationURL, options: .atomic)
            try auditRepository.record(
                AuditEvent(
                    eventType: .export,
                    objectType: "usage_events",
                    objectID: format.rawValue,
                    result: .success,
                    message: "导出 \(usageEvents.count) 条明细到 \(destinationURL.lastPathComponent)"
                )
            )
            statusMessage = "已导出 \(usageEvents.count) 条明细"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func requestCleanup() {
        pendingCleanupOptions = CleanupOptions()
        showingCleanupSheet = true
    }

    func exportDiagnostics() {
        do {
            let report = try buildDiagnosticsReport()
            let data = try diagnosticsExporter.export(report: report)
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = "codex-diagnostics-\(Self.exportDateFormatter.string(from: Date())).json"
            savePanel.allowedContentTypes = [.json]
            guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
                statusMessage = "已取消导出诊断"
                return
            }
            try data.write(to: destinationURL, options: .atomic)
            try auditRepository.record(
                AuditEvent(
                    eventType: .export,
                    objectType: "diagnostics",
                    objectID: "json",
                    result: .success,
                    message: "导出诊断包到 \(destinationURL.lastPathComponent)"
                )
            )
            statusMessage = "诊断包已导出"
        } catch {
            statusMessage = "导出诊断失败：\(error.localizedDescription)"
        }
    }

    func performCleanup(_ options: CleanupOptions) {
        do {
            try maintenanceRepository.performCleanup(
                options,
                accountRepository: accountRepository,
                keychainStore: keychainStore
            )
            if options.resetSettings {
                _ = try settingsRepository.ensureDefaultSettings()
            }
            try auditRepository.record(
                AuditEvent(
                    eventType: .cleanup,
                    objectType: "storage",
                    objectID: "local",
                    result: .success,
                    message: cleanupSummary(options)
                )
            )
            showingCleanupSheet = false
            usageFilter = .default
            auditFilter = .default
            reload(statusMessage: "数据清理已完成")
        } catch {
            statusMessage = "数据清理失败：\(error.localizedDescription)"
        }
    }

    private func switchErrorMessage(_ error: Error) -> String {
        if let error = error as? SwitchPreflightError {
            switch error {
            case let .targetNotFound(id):
                return "找不到目标账号 \(id.uuidString)"
            case let .targetDisabled(alias):
                return "目标账号已禁用：\(alias)"
            case let .authorizationExpired(alias):
                return "目标账号授权已过期：\(alias)"
            case let .authorizationRevoked(alias):
                return "目标账号授权已撤销：\(alias)"
            case let .cooldownActive(alias, remainingSeconds):
                return "目标账号处于切换冷却中：\(alias)，剩余 \(remainingSeconds) 秒"
            }
        }
        return error.localizedDescription
    }

    private func defaultExportFilename(format: UsageEventExportFormat) -> String {
        "codex-usage-events-\(Self.exportDateFormatter.string(from: Date())).\(format.fileExtension)"
    }

    private func contentTypes(for format: UsageEventExportFormat) -> [UTType] {
        switch format {
        case .csv:
            return [.commaSeparatedText]
        case .json:
            return [.json]
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func cleanupSummary(_ options: CleanupOptions) -> String {
        var parts: [String] = []
        if options.clearUsageEvents { parts.append("usage") }
        if options.clearSnapshots { parts.append("snapshots") }
        if options.clearCollectorOffsets { parts.append("offsets") }
        if options.clearAlerts { parts.append("alerts") }
        if options.clearSwitchEvents { parts.append("switch_events") }
        if options.clearAuditEvents { parts.append("audit") }
        if options.clearAccounts { parts.append("accounts") }
        if options.clearKeychainSecrets { parts.append("keychain_refs") }
        if options.resetSettings { parts.append("settings_reset") }
        return "清理项：\(parts.joined(separator: ", "))"
    }

    private func buildDiagnosticsReport() throws -> DiagnosticsReport {
        let codexRoot = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        let stateDatabaseURL = codexRoot.appending(path: "state_5.sqlite")
        let jsonlFileCount = countJSONLFiles(in: codexRoot)
        return DiagnosticsReport(
            appVersion: appVersionString(),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            collectorVersion: "local-jsonl+state-sqlite",
            settings: settings,
            storageSummary: try diagnosticsRepository.storageSummary(),
            sourceSummary: DiagnosticsSourceSummary(
                codexRootPath: codexRoot.path,
                codexRootReadable: FileManager.default.isReadableFile(atPath: codexRoot.path),
                jsonlFileCount: jsonlFileCount,
                stateDatabasePath: stateDatabaseURL.path,
                stateDatabaseReadable: FileManager.default.isReadableFile(atPath: stateDatabaseURL.path),
                parseFailuresTracked: false
            ),
            latestSnapshot: latestSnapshot.map(DiagnosticsSnapshotSummary.init(snapshot:)),
            lastErrorSummary: nil
        )
    }

    private func countJSONLFiles(in root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            count += 1
        }
        return count
    }

    private func appVersionString() -> String {
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "\(short) (\(build))"
        }
        return "dev"
    }

    private func beginAwaitingActiveSwitch(_ session: SwitchSession) {
        activeSwitchTask?.cancel()
        activeSwitchTask = Task { [weak self] in
            guard let self else {
                return
            }
            let outcome = await switchCoordinator.awaitCompletion(
                session,
                refreshSnapshot: { account in
                    try await Task.detached(priority: .utility) {
                        try await LocalQuotaRefreshService.collectLatestSnapshot(accountAlias: account.alias)
                    }.value
                }
            )
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self.activeSwitchTask = nil
                self.activeSwitchSession = nil
                self.reload(statusMessage: outcome.message)
            }
        }
    }
}
