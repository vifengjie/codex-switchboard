import CodexQuotaCore
import SwiftUI

struct ManagementRootView: View {
    @StateObject private var viewModel = ManagementViewModel()

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                OverviewTab(
                    accounts: viewModel.accounts,
                    settings: viewModel.settings,
                    latestSnapshot: viewModel.latestSnapshot
                )
                .tabItem { Text("总览") }

                AccountsTab(
                    accounts: viewModel.accounts,
                    addAction: viewModel.addLocalAccount,
                    toggleAction: viewModel.toggleEnabled(account:),
                    deleteAction: viewModel.delete(account:)
                )
                .tabItem { Text("账号") }

                DetailsTab(events: viewModel.usageEvents)
                    .tabItem { Text("明细") }

                PolicyTab(
                    settings: viewModel.settings,
                    saveAction: viewModel.saveSettings(_:)
                )
                .tabItem { Text("策略") }

                AuditTab(events: viewModel.auditEvents)
                    .tabItem { Text("审计") }
            }
            Divider()
            HStack {
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刷新") {
                    viewModel.reload()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

private struct OverviewTab: View {
    let accounts: [Account]
    let settings: AppSettings
    let latestSnapshot: QuotaSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Metric(label: "账号", value: "\(accounts.count)")
                Metric(label: "5H 阈值", value: "\(Int(settings.fiveHourRiskThresholdPercent))%")
                Metric(label: "1W 阈值", value: "\(Int(settings.weeklyCriticalThresholdPercent))%")
                Metric(label: "快照", value: latestSnapshot?.accountAlias ?? "未设置")
            }

            if let latestSnapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近快照")
                        .font(.headline)
                    Text("账号：\(latestSnapshot.accountAlias)")
                    Text("5H：\(formatPercent(latestSnapshot.fiveHourRemainingPercent))  1W：\(formatPercent(latestSnapshot.weeklyRemainingPercent))")
                    Text("可信度：\(latestSnapshot.confidence.rawValue)")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded()))%"
    }
}

private struct AccountsTab: View {
    let accounts: [Account]
    let addAction: () -> Void
    let toggleAction: (Account) -> Void
    let deleteAction: (Account) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("账号")
                    .font(.headline)
                Spacer()
                Button("添加账号", action: addAction)
            }

            Table(accounts) {
                TableColumn("别名") { account in
                    Text(account.alias)
                }
                TableColumn("Workspace") { account in
                    Text(account.workspaceName ?? "--")
                }
                TableColumn("邮箱") { account in
                    Text(account.emailMasked ?? "--")
                }
                TableColumn("Plan") { account in
                    Text(account.planType.rawValue)
                }
                TableColumn("授权") { account in
                    Text(account.authStatus.rawValue)
                }
                TableColumn("优先级") { account in
                    Text("\(account.priority)")
                }
                TableColumn("状态") { account in
                    Button(account.enabled ? "启用" : "禁用") {
                        toggleAction(account)
                    }
                }
                TableColumn("操作") { account in
                    Button("删除") {
                        deleteAction(account)
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct PolicyTab: View {
    let settings: AppSettings
    let saveAction: (AppSettings) -> Void
    @State private var draft: AppSettings

    init(settings: AppSettings, saveAction: @escaping (AppSettings) -> Void) {
        self.settings = settings
        self.saveAction = saveAction
        self._draft = State(initialValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Stepper(
                    "5H 风险阈值：\(Int(draft.fiveHourRiskThresholdPercent))%",
                    value: $draft.fiveHourRiskThresholdPercent,
                    in: 1...100,
                    step: 1
                )
                Stepper(
                    "1W 强提醒阈值：\(Int(draft.weeklyCriticalThresholdPercent))%",
                    value: $draft.weeklyCriticalThresholdPercent,
                    in: 1...100,
                    step: 1
                )
                Stepper(
                    "通知去重窗口：\(draft.notificationDedupeMinutes) 分钟",
                    value: $draft.notificationDedupeMinutes,
                    in: 1...240,
                    step: 5
                )
                Stepper(
                    "快照过期时间：\(draft.snapshotStaleMinutes) 分钟",
                    value: $draft.snapshotStaleMinutes,
                    in: 1...120,
                    step: 5
                )
                Toggle("Workspace 脱敏", isOn: $draft.redactWorkspaceNames)
                Toggle("线程标题脱敏", isOn: $draft.redactThreadTitles)
            }

            HStack {
                Button("恢复当前值") {
                    draft = settings
                }
                Spacer()
                Button("保存策略") {
                    saveAction(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == settings)
            }
        }
        .padding(20)
        .onChange(of: settings) { _, newValue in
            draft = newValue
        }
    }
}

private struct DetailsTab: View {
    let events: [UsageEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("明细")
                .font(.headline)

            if events.isEmpty {
                ContentUnavailableView("暂无用量明细", systemImage: "tablecells", description: Text("M2 接入本地采集器后会写入 usage events"))
            } else {
                Table(events) {
                    TableColumn("时间") { event in
                        Text(Self.dateFormatter.string(from: event.eventTime))
                    }
                    TableColumn("账号") { event in
                        Text(event.accountAlias ?? "--")
                    }
                    TableColumn("线程") { event in
                        Text(event.taskTitleMasked ?? event.threadID ?? "--")
                    }
                    TableColumn("模型") { event in
                        Text(event.model ?? "--")
                    }
                    TableColumn("Input") { event in
                        Text(Self.formatMTokens(event.inputMTokensDelta))
                    }
                    TableColumn("Cached") { event in
                        Text(Self.formatMTokens(event.cachedInputMTokensDelta))
                    }
                    TableColumn("Output") { event in
                        Text(Self.formatMTokens(event.outputMTokensDelta))
                    }
                    TableColumn("Credits") { event in
                        Text(Self.formatCredits(event.estimatedCreditsDelta))
                    }
                    TableColumn("Source") { event in
                        Text(event.source.rawValue)
                    }
                }
            }
        }
            .padding(20)
    }

    private static func formatMTokens(_ value: Double) -> String {
        if value > 0, value < 0.001 {
            return "<0.001M"
        }
        if value < 10 {
            return String(format: "%.3fM", value)
        }
        if value < 100 {
            return String(format: "%.2fM", value)
        }
        return String(format: "%.1fM", value)
    }

    private static func formatCredits(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.2f", value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct AuditTab: View {
    let events: [AuditEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("审计")
                .font(.headline)

            if events.isEmpty {
                ContentUnavailableView("暂无审计记录", systemImage: "list.bullet.clipboard", description: Text("账号新增、启用/禁用、删除会写入本地审计"))
            } else {
                Table(events) {
                    TableColumn("时间") { event in
                        Text(Self.dateFormatter.string(from: event.createdAt))
                    }
                    TableColumn("事件") { event in
                        Text(event.eventType.rawValue)
                    }
                    TableColumn("对象") { event in
                        Text(event.objectType ?? "--")
                    }
                    TableColumn("结果") { event in
                        Text(event.result.rawValue)
                    }
                    TableColumn("说明") { event in
                        Text(event.message ?? "--")
                    }
                }
            }
        }
        .padding(20)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(minWidth: 110, alignment: .leading)
    }
}
