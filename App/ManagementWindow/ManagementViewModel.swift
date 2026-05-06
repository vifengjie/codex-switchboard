import CodexQuotaCore
import CodexQuotaStorage
import Foundation

@MainActor
final class ManagementViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var latestSnapshot: QuotaSnapshot?
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var usageEvents: [UsageEvent] = []
    @Published private(set) var statusMessage = "就绪"

    private let store: SQLiteStore
    private let usageEventRepository: SQLiteUsageEventRepository
    private let auditRepository: SQLiteAuditRepository
    private let accountRepository: SQLiteAccountRepository
    private let settingsRepository: SQLiteSettingsRepository
    private let snapshotRepository: SQLiteSnapshotRepository

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

        self.store = resolvedStore
        self.usageEventRepository = SQLiteUsageEventRepository(store: resolvedStore)
        self.auditRepository = SQLiteAuditRepository(store: resolvedStore)
        self.accountRepository = SQLiteAccountRepository(store: resolvedStore)
        self.settingsRepository = SQLiteSettingsRepository(store: resolvedStore)
        self.snapshotRepository = SQLiteSnapshotRepository(store: resolvedStore)
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
        do {
            let nextIndex = accounts.count + 1
            let account = Account(
                alias: "本地账号 \(nextIndex)",
                workspaceName: nil,
                emailMasked: nil,
                planType: .unknown,
                authStatus: .unknown,
                enabled: true,
                priority: max(0, 100 - nextIndex)
            )
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
        } catch {
            statusMessage = "添加账号失败：\(error.localizedDescription)"
        }
    }

    func toggleEnabled(account: Account) {
        do {
            var updated = account
            updated.enabled.toggle()
            try accountRepository.upsert(updated)
            try auditRepository.record(
                AuditEvent(
                    eventType: .accountUpdate,
                    objectType: "account",
                    objectID: updated.id.uuidString,
                    result: .success,
                    message: "\(updated.enabled ? "启用" : "禁用")账号：\(updated.alias)"
                )
            )
            reload(statusMessage: "账号状态已更新并写入审计")
        } catch {
            statusMessage = "更新账号失败：\(error.localizedDescription)"
        }
    }

    func delete(account: Account) {
        do {
            try accountRepository.delete(id: account.id)
            try auditRepository.record(
                AuditEvent(
                    eventType: .accountDelete,
                    objectType: "account",
                    objectID: account.id.uuidString,
                    result: .success,
                    message: "删除账号：\(account.alias)"
                )
            )
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
}
