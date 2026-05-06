import CodexQuotaCore
import CodexQuotaExport
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
                    .environmentObject(viewModel)
                    .tabItem { Text("明细") }

                PolicyTab(
                    settings: viewModel.settings,
                    saveAction: viewModel.saveSettings(_:),
                    cleanupAction: viewModel.requestCleanup,
                    diagnosticsAction: viewModel.exportDiagnostics
                )
                .tabItem { Text("策略") }

                AuditTab(events: viewModel.auditEvents)
                    .environmentObject(viewModel)
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
        .sheet(isPresented: $viewModel.showingCleanupSheet) {
            CleanupSheet(
                options: viewModel.pendingCleanupOptions,
                confirmAction: viewModel.performCleanup(_:),
                cancelAction: {
                    viewModel.showingCleanupSheet = false
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
                TableColumn("登录标识") { account in
                    Text(account.loginIdentifierMasked ?? "--")
                }
                TableColumn("Plan") { account in
                    Text(account.planType.rawValue)
                }
                TableColumn("二次验证") { account in
                    Text(verificationSummary(for: account))
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

    private func verificationSummary(for account: Account) -> String {
        let labels = account.verificationMethods.map { method in
            switch method {
            case .emailOTP:
                return "邮箱"
            case .authenticatorTOTP:
                return "Authenticator"
            case .smsOTP:
                return "短信"
            case .unknown:
                return "其他"
            }
        }
        return labels.isEmpty ? "--" : labels.joined(separator: " + ")
    }
}

private struct AccountEditorDraft: Identifiable {
    let id: UUID
    var isNew: Bool
    var alias: String
    var provider: AccountProvider
    var workspaceName: String
    var emailMasked: String
    var loginIdentifierMasked: String
    var planType: PlanType
    var seatType: SeatType
    var authMethod: AuthMethod
    var authStatus: AuthStatus
    var passwordRequired: Bool
    var verificationMethods: Set<VerificationMethod>
    var verificationHint: String
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
            loginIdentifierMasked: "",
            planType: .unknown,
            seatType: .unknown,
            authMethod: .unknown,
            authStatus: .unknown,
            passwordRequired: false,
            verificationMethods: [],
            verificationHint: "",
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
        self.loginIdentifierMasked = account.loginIdentifierMasked ?? ""
        self.planType = account.planType
        self.seatType = account.seatType
        self.authMethod = account.authMethod
        self.authStatus = account.authStatus
        self.passwordRequired = account.passwordRequired
        self.verificationMethods = Set(account.verificationMethods)
        self.verificationHint = account.verificationHint ?? ""
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
        loginIdentifierMasked: String,
        planType: PlanType,
        seatType: SeatType,
        authMethod: AuthMethod,
        authStatus: AuthStatus,
        passwordRequired: Bool,
        verificationMethods: Set<VerificationMethod>,
        verificationHint: String,
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
        self.loginIdentifierMasked = loginIdentifierMasked
        self.planType = planType
        self.seatType = seatType
        self.authMethod = authMethod
        self.authStatus = authStatus
        self.passwordRequired = passwordRequired
        self.verificationMethods = verificationMethods
        self.verificationHint = verificationHint
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
            loginIdentifierMasked: optionalText(loginIdentifierMasked),
            planType: planType,
            seatType: seatType,
            authMethod: authMethod,
            authStatus: authStatus,
            passwordRequired: passwordRequired,
            verificationMethods: verificationMethods.sorted { $0.rawValue < $1.rawValue },
            verificationHint: optionalText(verificationHint),
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
                TextField("登录标识（脱敏）", text: $draft.loginIdentifierMasked)
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
                Toggle("需要密码", isOn: $draft.passwordRequired)
                VStack(alignment: .leading, spacing: 8) {
                    Text("二次验证")
                        .font(.subheadline)
                    Toggle("邮箱验证码", isOn: verificationMethodBinding(.emailOTP))
                    Toggle("Authenticator 动态码", isOn: verificationMethodBinding(.authenticatorTOTP))
                    Toggle("短信验证码", isOn: verificationMethodBinding(.smsOTP))
                    Toggle("其他验证码", isOn: verificationMethodBinding(.unknown))
                }
                TextField("二次验证提示", text: $draft.verificationHint)
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

    private func verificationMethodBinding(_ method: VerificationMethod) -> Binding<Bool> {
        Binding(
            get: { draft.verificationMethods.contains(method) },
            set: { enabled in
                if enabled {
                    draft.verificationMethods.insert(method)
                } else {
                    draft.verificationMethods.remove(method)
                }
            }
        )
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
                Text("登录资料：\(credentialSummary(preflight.targetAccount))")
                if let verificationSummary = verificationSummary(preflight.targetAccount) {
                    Text("二次验证：\(verificationSummary)")
                }
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
        case .additionalVerificationRequired:
            return "该账号需要额外验证码，请提前准备邮箱或 Authenticator。"
        }
    }

    private func credentialSummary(_ account: Account) -> String {
        var parts: [String] = []
        if let loginIdentifierMasked = account.loginIdentifierMasked, !loginIdentifierMasked.isEmpty {
            parts.append(loginIdentifierMasked)
        }
        if account.passwordRequired {
            parts.append("需要密码")
        }
        return parts.isEmpty ? "--" : parts.joined(separator: " / ")
    }

    private func verificationSummary(_ account: Account) -> String? {
        let methods = account.verificationMethods.map { method in
            switch method {
            case .emailOTP:
                return "邮箱验证码"
            case .authenticatorTOTP:
                return "Authenticator 动态码"
            case .smsOTP:
                return "短信验证码"
            case .unknown:
                return "其他验证码"
            }
        }
        guard !methods.isEmpty else {
            return nil
        }
        if let verificationHint = account.verificationHint, !verificationHint.isEmpty {
            return "\(methods.joined(separator: " + "))（\(verificationHint)）"
        }
        return methods.joined(separator: " + ")
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
    let cleanupAction: () -> Void
    let diagnosticsAction: () -> Void
    @State private var draft: AppSettings

    init(
        settings: AppSettings,
        saveAction: @escaping (AppSettings) -> Void,
        cleanupAction: @escaping () -> Void,
        diagnosticsAction: @escaping () -> Void
    ) {
        self.settings = settings
        self.saveAction = saveAction
        self.cleanupAction = cleanupAction
        self.diagnosticsAction = diagnosticsAction
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
                Button("导出诊断", action: diagnosticsAction)
                Button("清理数据", action: cleanupAction)
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
    @EnvironmentObject private var viewModel: ManagementViewModel
    let events: [UsageEvent]
    @State private var draftFilter = UsageEventFilter.default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("明细")
                    .font(.headline)
                Spacer()
                Button("导出 CSV") {
                    viewModel.exportUsageEvents(format: .csv)
                }
                Button("导出 JSON") {
                    viewModel.exportUsageEvents(format: .json)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    TextField("账号", text: binding(for: \.accountAlias))
                    TextField("模型", text: binding(for: \.model))
                    Picker("来源", selection: $draftFilter.source) {
                        Text("全部").tag(UsageEventSource?.none)
                        ForEach(sourceOptions(), id: \.self) { value in
                            Text(value.rawValue).tag(Optional(value))
                        }
                    }
                }
                HStack(spacing: 12) {
                    TextField("线程 / 标题", text: binding(for: \.threadQuery))
                    DatePicker("开始", selection: binding(for: \.dateFrom, defaultValue: Date()), displayedComponents: [.date, .hourAndMinute])
                    Toggle("启用", isOn: hasDateFromBinding)
                    DatePicker("结束", selection: binding(for: \.dateTo, defaultValue: Date()), displayedComponents: [.date, .hourAndMinute])
                    Toggle("启用", isOn: hasDateToBinding)
                }
                HStack {
                    Stepper("数量：\(draftFilter.limit)", value: $draftFilter.limit, in: 10...2000, step: 10)
                    Spacer()
                    Button("重置筛选") {
                        draftFilter = .default
                        viewModel.resetUsageFilter()
                    }
                    Button("应用筛选") {
                        viewModel.applyUsageFilter(normalizedFilter())
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

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
        .onAppear {
            draftFilter = viewModel.usageFilter
        }
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

    private func binding(for keyPath: WritableKeyPath<UsageEventFilter, String?>) -> Binding<String> {
        Binding(
            get: { draftFilter[keyPath: keyPath] ?? "" },
            set: { draftFilter[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func binding(for keyPath: WritableKeyPath<UsageEventFilter, Date?>, defaultValue: Date) -> Binding<Date> {
        Binding(
            get: { draftFilter[keyPath: keyPath] ?? defaultValue },
            set: { draftFilter[keyPath: keyPath] = $0 }
        )
    }

    private var hasDateFromBinding: Binding<Bool> {
        Binding(
            get: { draftFilter.dateFrom != nil },
            set: { draftFilter.dateFrom = $0 ? (draftFilter.dateFrom ?? Date()) : nil }
        )
    }

    private var hasDateToBinding: Binding<Bool> {
        Binding(
            get: { draftFilter.dateTo != nil },
            set: { draftFilter.dateTo = $0 ? (draftFilter.dateTo ?? Date()) : nil }
        )
    }

    private func normalizedFilter() -> UsageEventFilter {
        UsageEventFilter(
            accountAlias: normalizedText(draftFilter.accountAlias),
            model: normalizedText(draftFilter.model),
            threadQuery: normalizedText(draftFilter.threadQuery),
            source: draftFilter.source,
            dateFrom: draftFilter.dateFrom,
            dateTo: draftFilter.dateTo,
            limit: draftFilter.limit
        )
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sourceOptions() -> [UsageEventSource] {
        [.localJSONL, .stateSQLite, .cliStatus, .officialAPI, .importedReport, .manual]
    }
}

private struct AuditTab: View {
    @EnvironmentObject private var viewModel: ManagementViewModel
    let events: [AuditEvent]
    @State private var draftFilter = AuditEventFilter.default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("审计")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 12) {
                Picker("事件", selection: $draftFilter.eventType) {
                    Text("全部").tag(AuditEventType?.none)
                    ForEach(AuditEventType.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(Optional(value))
                    }
                }
                Picker("结果", selection: $draftFilter.result) {
                    Text("全部").tag(AuditResult?.none)
                    ForEach(AuditResult.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(Optional(value))
                    }
                }
                TextField("对象 / 说明", text: binding(for: \.query))
                Stepper("数量：\(draftFilter.limit)", value: $draftFilter.limit, in: 10...1000, step: 10)
                Button("重置筛选") {
                    draftFilter = .default
                    viewModel.resetAuditFilter()
                }
                Button("应用筛选") {
                    viewModel.applyAuditFilter(normalizedFilter())
                }
            }

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
        .onAppear {
            draftFilter = viewModel.auditFilter
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func binding(for keyPath: WritableKeyPath<AuditEventFilter, String?>) -> Binding<String> {
        Binding(
            get: { draftFilter[keyPath: keyPath] ?? "" },
            set: { draftFilter[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func normalizedFilter() -> AuditEventFilter {
        AuditEventFilter(
            eventType: draftFilter.eventType,
            result: draftFilter.result,
            query: normalizedText(draftFilter.query),
            limit: draftFilter.limit
        )
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CleanupSheet: View {
    @State private var options: CleanupOptions
    let confirmAction: (CleanupOptions) -> Void
    let cancelAction: () -> Void

    init(
        options: CleanupOptions,
        confirmAction: @escaping (CleanupOptions) -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self._options = State(initialValue: options)
        self.confirmAction = confirmAction
        self.cancelAction = cancelAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("清理数据")
                .font(.headline)

            Form {
                Toggle("清理明细 events", isOn: $options.clearUsageEvents)
                Toggle("清理 quota snapshots", isOn: $options.clearSnapshots)
                Toggle("清理 collector offsets", isOn: $options.clearCollectorOffsets)
                Toggle("清理 alerts", isOn: $options.clearAlerts)
                Toggle("清理 switch events", isOn: $options.clearSwitchEvents)
                Toggle("清理 audit events", isOn: $options.clearAuditEvents)
                Toggle("清理账号元数据", isOn: $options.clearAccounts)
                Toggle("删除 Keychain 引用", isOn: $options.clearKeychainSecrets)
                    .disabled(!options.clearAccounts)
                Toggle("重置设置为默认值", isOn: $options.resetSettings)
            }

            Text("只会清理本应用自己的 SQLite 和 Keychain 引用，不会读取、复制或删除 Codex 自身 auth 文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消", action: cancelAction)
                Spacer()
                Button("确认清理") {
                    confirmAction(options)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
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
