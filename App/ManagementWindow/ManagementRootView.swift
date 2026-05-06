import CodexQuotaCore
import CodexQuotaSwitch
import SwiftUI

struct ManagementRootView: View {
    @StateObject private var viewModel = ManagementViewModel()
    @State private var accountEditorDraft: AccountEditorDraft?

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
                    addAction: {
                        accountEditorDraft = .new(nextIndex: viewModel.accounts.count + 1)
                    },
                    editAction: { account in
                        accountEditorDraft = AccountEditorDraft(account: account)
                    },
                    toggleAction: viewModel.toggleEnabled(account:),
                    deleteAction: viewModel.delete(account:),
                    switchAction: viewModel.prepareSwitch(account:)
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
        .sheet(item: $accountEditorDraft) { draft in
            AccountEditorSheet(
                draft: draft,
                saveAction: { account in
                    viewModel.saveAccount(account)
                    accountEditorDraft = nil
                },
                cancelAction: {
                    accountEditorDraft = nil
                }
            )
        }
        .sheet(item: $viewModel.pendingSwitchPreflight) { preflight in
            SwitchConfirmationSheet(
                preflight: preflight,
                confirmAction: viewModel.launchPreparedSwitch,
                cancelAction: viewModel.cancelPreparedSwitch
            )
        }
        .sheet(item: $viewModel.activeSwitchSession) { session in
            SwitchCompletionSheet(
                session: session,
                completeAction: {
                    viewModel.completeActiveSwitchSession(userConfirmed: true)
                },
                cancelAction: {
                    viewModel.completeActiveSwitchSession(userConfirmed: false)
                }
            )
        }
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
    let editAction: (Account) -> Void
    let toggleAction: (Account) -> Void
    let deleteAction: (Account) -> Void
    let switchAction: (Account) -> Void

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
                    HStack(spacing: 8) {
                        Button("编辑") {
                            editAction(account)
                        }
                        Button("切换") {
                            switchAction(account)
                        }
                        Button("删除") {
                            deleteAction(account)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct AccountEditorDraft: Identifiable {
    let id: UUID
    var isNew: Bool
    var alias: String
    var provider: AccountProvider
    var workspaceName: String
    var emailMasked: String
    var planType: PlanType
    var seatType: SeatType
    var authMethod: AuthMethod
    var authStatus: AuthStatus
    var keychainRef: String
    var enabled: Bool
    var priority: Int
    var lastSwitchedAt: Date?

    static func new(nextIndex: Int) -> AccountEditorDraft {
        AccountEditorDraft(
            id: UUID(),
            isNew: true,
            alias: "本地账号 \(nextIndex)",
            provider: .chatgpt,
            workspaceName: "",
            emailMasked: "",
            planType: .unknown,
            seatType: .unknown,
            authMethod: .unknown,
            authStatus: .unknown,
            keychainRef: "",
            enabled: true,
            priority: max(0, 100 - nextIndex),
            lastSwitchedAt: nil
        )
    }

    init(account: Account) {
        self.id = account.id
        self.isNew = false
        self.alias = account.alias
        self.provider = account.provider
        self.workspaceName = account.workspaceName ?? ""
        self.emailMasked = account.emailMasked ?? ""
        self.planType = account.planType
        self.seatType = account.seatType
        self.authMethod = account.authMethod
        self.authStatus = account.authStatus
        self.keychainRef = account.keychainRef ?? ""
        self.enabled = account.enabled
        self.priority = account.priority
        self.lastSwitchedAt = account.lastSwitchedAt
    }

    private init(
        id: UUID,
        isNew: Bool,
        alias: String,
        provider: AccountProvider,
        workspaceName: String,
        emailMasked: String,
        planType: PlanType,
        seatType: SeatType,
        authMethod: AuthMethod,
        authStatus: AuthStatus,
        keychainRef: String,
        enabled: Bool,
        priority: Int,
        lastSwitchedAt: Date?
    ) {
        self.id = id
        self.isNew = isNew
        self.alias = alias
        self.provider = provider
        self.workspaceName = workspaceName
        self.emailMasked = emailMasked
        self.planType = planType
        self.seatType = seatType
        self.authMethod = authMethod
        self.authStatus = authStatus
        self.keychainRef = keychainRef
        self.enabled = enabled
        self.priority = priority
        self.lastSwitchedAt = lastSwitchedAt
    }

    var canSave: Bool {
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var account: Account {
        Account(
            id: id,
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: provider,
            workspaceName: optionalText(workspaceName),
            emailMasked: optionalText(emailMasked),
            planType: planType,
            seatType: seatType,
            authMethod: authMethod,
            authStatus: authStatus,
            keychainRef: optionalText(keychainRef),
            enabled: enabled,
            priority: priority,
            lastSwitchedAt: lastSwitchedAt
        )
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AccountEditorSheet: View {
    @State private var draft: AccountEditorDraft
    let saveAction: (Account) -> Void
    let cancelAction: () -> Void

    init(
        draft: AccountEditorDraft,
        saveAction: @escaping (Account) -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.saveAction = saveAction
        self.cancelAction = cancelAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.isNew ? "添加账号" : "编辑账号")
                .font(.headline)

            Form {
                TextField("别名", text: $draft.alias)
                TextField("Workspace", text: $draft.workspaceName)
                TextField("邮箱（脱敏）", text: $draft.emailMasked)
                Picker("Provider", selection: $draft.provider) {
                    ForEach(AccountProvider.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("Plan", selection: $draft.planType) {
                    ForEach(PlanType.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("Seat", selection: $draft.seatType) {
                    ForEach(SeatType.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("授权方式", selection: $draft.authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("授权状态", selection: $draft.authStatus) {
                    ForEach(AuthStatus.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField("Keychain 引用", text: $draft.keychainRef)
                Stepper("优先级：\(draft.priority)", value: $draft.priority, in: 0...999, step: 1)
                Toggle("启用", isOn: $draft.enabled)
            }

            HStack {
                Button("取消", action: cancelAction)
                Spacer()
                Button("保存") {
                    saveAction(draft.account)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct SwitchConfirmationSheet: View {
    let preflight: SwitchPreflight
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认切换账号")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("当前账号：\(preflight.fromAccount?.alias ?? preflight.currentSnapshot?.accountAlias ?? "未设置")")
                Text("目标账号：\(preflight.targetAccount.alias)")
                Text("目标额度：\(quotaLine(preflight.targetSnapshot))")
                Text("授权状态：\(preflight.targetAccount.authStatus.rawValue)")
            }

            if !preflight.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("注意")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(preflight.warnings, id: \.rawValue) { warning in
                        Text(warningText(warning))
                    }
                }
                .foregroundStyle(.secondary)
            }

            Text(preflight.privacyNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消", action: cancelAction)
                Spacer()
                Button("打开官方流程", action: confirmAction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func quotaLine(_ snapshot: QuotaSnapshot?) -> String {
        guard let snapshot else {
            return "--"
        }
        return "5H \(formatPercent(snapshot.fiveHourRemainingPercent)) / 1W \(formatPercent(snapshot.weeklyRemainingPercent))"
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded()))%"
    }

    private func warningText(_ warning: SwitchPreflightWarning) -> String {
        switch warning {
        case .authorizationUnknown:
            return "授权状态未知，完成官方流程后会按用户确认刷新。"
        case .snapshotMissing:
            return "目标账号暂无额度快照，切换后会强制刷新。"
        case .snapshotStale:
            return "目标账号快照已过期，切换后会强制刷新。"
        }
    }
}

private struct SwitchCompletionSheet: View {
    let session: SwitchSession
    let completeAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("完成官方流程")
                .font(.headline)
            Text("目标账号：\(session.preflight.targetAccount.alias)")

            VStack(alignment: .leading, spacing: 6) {
                ForEach(session.launch.instructions, id: \.self) { instruction in
                    Text(instruction)
                }
            }
            .foregroundStyle(.secondary)

            HStack {
                Button("取消切换", action: cancelAction)
                Spacer()
                Button("我已完成切换", action: completeAction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
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
