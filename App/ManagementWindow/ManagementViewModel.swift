import AppKit
import CodexQuotaCore
import CodexQuotaStorage
import CodexQuotaSwitch
import Foundation

@MainActor
final class ManagementViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var latestSnapshot: QuotaSnapshot?
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var usageEvents: [UsageEvent] = []
    @Published private(set) var statusMessage = "就绪"
    @Published var pendingSwitchPreflight: SwitchPreflight?
    @Published var activeSwitchSession: SwitchSession?

    private let store: SQLiteStore
    private let usageEventRepository: SQLiteUsageEventRepository
    private let auditRepository: SQLiteAuditRepository
    private let accountRepository: SQLiteAccountRepository
    private let settingsRepository: SQLiteSettingsRepository
    private let snapshotRepository: SQLiteSnapshotRepository
    private let switchEventRepository: SQLiteSwitchEventRepository
    private let accountManager: AccountManager
    private let switchCoordinator: SwitchCoordinator

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

        self.store = resolvedStore
        self.usageEventRepository = resolvedUsageEventRepository
        self.auditRepository = resolvedAuditRepository
        self.accountRepository = resolvedAccountRepository
        self.settingsRepository = resolvedSettingsRepository
        self.snapshotRepository = resolvedSnapshotRepository
        self.switchEventRepository = resolvedSwitchEventRepository
        self.accountManager = AccountManager(
            accountRepository: resolvedAccountRepository,
            auditRepository: resolvedAuditRepository
        )
        self.switchCoordinator = SwitchCoordinator(
            accountRepository: resolvedAccountRepository,
            snapshotRepository: resolvedSnapshotRepository,
            switchEventRepository: resolvedSwitchEventRepository,
            auditRepository: resolvedAuditRepository,
            provider: OfficialLoginSwitchProvider(
                openURL: { url in
                    await MainActor.run {
                        NSWorkspace.shared.open(url)
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
            auditEvents = try auditRepository.recent(limit: 100)
            usageEvents = try usageEventRepository.recent(limit: 200)
            self.statusMessage = statusMessage
        } catch {
            self.statusMessage = "刷新失败：\(error.localizedDescription)"
        }
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
                statusMessage = "官方流程已打开，完成后请回到本窗口确认"
            } catch {
                pendingSwitchPreflight = nil
                reload(statusMessage: "启动切换失败：\(error.localizedDescription)")
            }
        }
    }

    func completeActiveSwitchSession(userConfirmed: Bool) {
        guard let session = activeSwitchSession else {
            return
        }
        statusMessage = userConfirmed ? "正在校验并刷新目标账号快照..." : "正在取消切换..."
        Task {
            let outcome = await switchCoordinator.complete(
                session,
                officialFlowConfirmedByUser: userConfirmed,
                refreshSnapshot: { account in
                    try await Task.detached(priority: .utility) {
                        try await LocalQuotaRefreshService.collectLatestSnapshot(accountAlias: account.alias)
                    }.value
                }
            )
            activeSwitchSession = nil
            reload(statusMessage: outcome.message)
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
}
