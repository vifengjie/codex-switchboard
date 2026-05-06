import CodexQuotaCore
import Foundation

public enum SwitchPreflightError: Error, Equatable, Sendable {
    case targetNotFound(UUID)
    case targetDisabled(String)
    case authorizationExpired(String)
    case authorizationRevoked(String)
    case cooldownActive(String, remainingSeconds: Int)
}

public enum SwitchPreflightWarning: String, Equatable, Sendable {
    case authorizationUnknown = "authorization_unknown"
    case snapshotMissing = "snapshot_missing"
    case snapshotStale = "snapshot_stale"
    case additionalVerificationRequired = "additional_verification_required"
}

public struct SwitchPreflight: Equatable, Identifiable, Sendable {
    public var id: UUID { targetAccount.id }
    public var fromAccount: Account?
    public var targetAccount: Account
    public var currentSnapshot: QuotaSnapshot?
    public var targetSnapshot: QuotaSnapshot?
    public var warnings: [SwitchPreflightWarning]
    public var reason: SwitchReason
    public var privacyNotice: String

    public init(
        fromAccount: Account?,
        targetAccount: Account,
        currentSnapshot: QuotaSnapshot?,
        targetSnapshot: QuotaSnapshot?,
        warnings: [SwitchPreflightWarning],
        reason: SwitchReason,
        privacyNotice: String
    ) {
        self.fromAccount = fromAccount
        self.targetAccount = targetAccount
        self.currentSnapshot = currentSnapshot
        self.targetSnapshot = targetSnapshot
        self.warnings = warnings
        self.reason = reason
        self.privacyNotice = privacyNotice
    }
}

public struct SwitchSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var preflight: SwitchPreflight
    public var launch: SwitchProviderLaunch
    public var phases: [SwitchPhase]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        preflight: SwitchPreflight,
        launch: SwitchProviderLaunch,
        phases: [SwitchPhase],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.preflight = preflight
        self.launch = launch
        self.phases = phases
        self.createdAt = createdAt
    }
}

public struct SwitchOutcome: Equatable, Sendable {
    public var result: SwitchEventResult
    public var targetAccount: Account?
    public var snapshot: QuotaSnapshot?
    public var phases: [SwitchPhase]
    public var message: String

    public init(
        result: SwitchEventResult,
        targetAccount: Account?,
        snapshot: QuotaSnapshot?,
        phases: [SwitchPhase],
        message: String
    ) {
        self.result = result
        self.targetAccount = targetAccount
        self.snapshot = snapshot
        self.phases = phases
        self.message = message
    }
}

public struct SwitchCoordinator: Sendable {
    private let accountRepository: any SwitchAccountRepository
    private let snapshotRepository: any SwitchSnapshotRepository
    private let switchEventRepository: any SwitchEventRepository
    private let auditRepository: any SwitchAuditRepository
    private let provider: any SwitchProvider
    private let snapshotStaleInterval: TimeInterval
    private let cooldownInterval: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        accountRepository: any SwitchAccountRepository,
        snapshotRepository: any SwitchSnapshotRepository,
        switchEventRepository: any SwitchEventRepository,
        auditRepository: any SwitchAuditRepository,
        provider: any SwitchProvider,
        snapshotStaleInterval: TimeInterval = 15 * 60,
        cooldownInterval: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountRepository = accountRepository
        self.snapshotRepository = snapshotRepository
        self.switchEventRepository = switchEventRepository
        self.auditRepository = auditRepository
        self.provider = provider
        self.snapshotStaleInterval = snapshotStaleInterval
        self.cooldownInterval = cooldownInterval
        self.now = now
    }

    public func preflight(
        targetAccountID: UUID,
        reason: SwitchReason = .userRequested
    ) throws -> SwitchPreflight {
        guard let target = try accountRepository.account(id: targetAccountID) else {
            throw SwitchPreflightError.targetNotFound(targetAccountID)
        }
        guard target.enabled else {
            throw SwitchPreflightError.targetDisabled(target.alias)
        }
        switch target.authStatus {
        case .expired:
            throw SwitchPreflightError.authorizationExpired(target.alias)
        case .revoked:
            throw SwitchPreflightError.authorizationRevoked(target.alias)
        case .active, .unknown:
            break
        }
        if let lastSwitchedAt = target.lastSwitchedAt {
            let remaining = cooldownInterval - now().timeIntervalSince(lastSwitchedAt)
            if remaining > 0 {
                throw SwitchPreflightError.cooldownActive(
                    target.alias,
                    remainingSeconds: Int(remaining.rounded(.up))
                )
            }
        }

        let accounts = try accountRepository.listAccounts()
        let currentSnapshot = try snapshotRepository.latestSnapshot()
        let targetSnapshot = try snapshotRepository.latestSnapshot(accountAlias: target.alias)
        let fromAccount = currentSnapshot.flatMap { snapshot in
            accounts.first { $0.alias == snapshot.accountAlias }
        }

        return SwitchPreflight(
            fromAccount: fromAccount,
            targetAccount: target,
            currentSnapshot: currentSnapshot,
            targetSnapshot: targetSnapshot,
            warnings: warnings(for: target, targetSnapshot: targetSnapshot),
            reason: reason,
            privacyNotice: "将打开官方登录或账号选择流程；本应用不会读取、复制或替换 Codex auth 文件，也不会导出 token、cookie 或聊天正文。"
        )
    }

    public func launch(_ preflight: SwitchPreflight) async throws -> SwitchSession {
        let phases: [SwitchPhase] = [.preflight, .confirmation, .launching]
        do {
            let launch = try await provider.launchSwitchFlow(
                from: preflight.fromAccount,
                to: preflight.targetAccount
            )
            return SwitchSession(
                preflight: preflight,
                launch: launch,
                phases: phases + [.waitingOfficialFlow],
                createdAt: now()
            )
        } catch {
            let message = "启动官方切换流程失败：\(error.localizedDescription)"
            try recordFinalEvent(
                preflight: preflight,
                result: .failed,
                message: message,
                providerName: provider.providerName,
                createdAt: now()
            )
            throw error
        }
    }

    public func complete(
        _ session: SwitchSession,
        officialFlowConfirmedByUser: Bool,
        refreshSnapshot: @escaping @Sendable (Account) async throws -> QuotaSnapshot?
    ) async -> SwitchOutcome {
        var phases = session.phases
        let preflight = session.preflight

        guard officialFlowConfirmedByUser else {
            phases.append(.cancelled)
            let message = "用户取消切换到：\(preflight.targetAccount.alias)"
            try? recordFinalEvent(
                preflight: preflight,
                result: .cancelled,
                message: message,
                providerName: session.launch.providerName,
                createdAt: now()
            )
            return SwitchOutcome(
                result: .cancelled,
                targetAccount: preflight.targetAccount,
                snapshot: nil,
                phases: phases,
                message: message
            )
        }

        do {
            phases.append(.verifying)
            let verification = try await provider.verifySwitch(
                to: preflight.targetAccount,
                userConfirmedOfficialFlow: officialFlowConfirmedByUser
            )
            guard verification.verified else {
                phases.append(.failed)
                try recordFinalEvent(
                    preflight: preflight,
                    result: .failed,
                    message: verification.message,
                    providerName: session.launch.providerName,
                    createdAt: now()
                )
                return SwitchOutcome(
                    result: .failed,
                    targetAccount: preflight.targetAccount,
                    snapshot: nil,
                    phases: phases,
                    message: verification.message
                )
            }

            phases.append(.refreshing)
            let refreshedSnapshot = try await refreshSnapshot(preflight.targetAccount)
            if let refreshedSnapshot {
                let result: SwitchEventResult = refreshedSnapshot.confidence == .failed || refreshedSnapshot.confidence == .stale
                    ? .staleSucceeded
                    : .success
                let terminalPhase: SwitchPhase = result == .success ? .succeeded : .staleSucceeded
                var snapshot = refreshedSnapshot
                snapshot.accountAlias = preflight.targetAccount.alias
                try snapshotRepository.save(snapshot)
                let updatedAccount = try markTargetSwitched(preflight.targetAccount)
                phases.append(terminalPhase)
                let message = result == .success
                    ? "已切换到：\(updatedAccount.alias)，并刷新快照"
                    : "已切换到：\(updatedAccount.alias)，但快照过期或刷新失败"
                try recordFinalEvent(
                    preflight: preflight,
                    result: result,
                    message: message,
                    providerName: session.launch.providerName,
                    createdAt: now()
                )
                return SwitchOutcome(
                    result: result,
                    targetAccount: updatedAccount,
                    snapshot: snapshot,
                    phases: phases,
                    message: message
                )
            }

            let staleSnapshot = try saveStaleSnapshot(for: preflight.targetAccount)
            let updatedAccount = try markTargetSwitched(preflight.targetAccount)
            phases.append(.staleSucceeded)
            let message = "已切换到：\(updatedAccount.alias)，但暂未获得新额度快照"
            try recordFinalEvent(
                preflight: preflight,
                result: .staleSucceeded,
                message: message,
                providerName: session.launch.providerName,
                createdAt: now()
            )
            return SwitchOutcome(
                result: .staleSucceeded,
                targetAccount: updatedAccount,
                snapshot: staleSnapshot,
                phases: phases,
                message: message
            )
        } catch {
            let staleSnapshot = try? saveStaleSnapshot(for: preflight.targetAccount)
            let updatedAccount = try? markTargetSwitched(preflight.targetAccount)
            phases.append(.staleSucceeded)
            let message = "已按用户确认切换到：\(preflight.targetAccount.alias)，但刷新失败：\(error.localizedDescription)"
            try? recordFinalEvent(
                preflight: preflight,
                result: .staleSucceeded,
                message: message,
                providerName: session.launch.providerName,
                createdAt: now()
            )
            return SwitchOutcome(
                result: .staleSucceeded,
                targetAccount: updatedAccount ?? preflight.targetAccount,
                snapshot: staleSnapshot,
                phases: phases,
                message: message
            )
        }
    }

    public func awaitCompletion(
        _ session: SwitchSession,
        timeoutSeconds: TimeInterval = 180,
        pollIntervalSeconds: TimeInterval = 2,
        refreshSnapshot: @escaping @Sendable (Account) async throws -> QuotaSnapshot?
    ) async -> SwitchOutcome {
        let deadline = now().addingTimeInterval(timeoutSeconds)
        var lastMessage = "等待 Codex 登录完成"

        while now() < deadline {
            if Task.isCancelled {
                return await complete(
                    session,
                    officialFlowConfirmedByUser: false,
                    refreshSnapshot: refreshSnapshot
                )
            }

            do {
                let verification = try await provider.verifySwitch(
                    to: session.preflight.targetAccount,
                    userConfirmedOfficialFlow: true
                )
                if verification.verified {
                    return await complete(
                        session,
                        officialFlowConfirmedByUser: true,
                        refreshSnapshot: refreshSnapshot
                    )
                }
                if !verification.message.isEmpty {
                    lastMessage = verification.message
                }
            } catch {
                lastMessage = error.localizedDescription
            }

            let intervalNanoseconds = UInt64(max(pollIntervalSeconds, 0.5) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }

        let message = "等待 Codex 登录超时：\(lastMessage)"
        try? recordFinalEvent(
            preflight: session.preflight,
            result: .failed,
            message: message,
            providerName: session.launch.providerName,
            createdAt: now()
        )
        return SwitchOutcome(
            result: .failed,
            targetAccount: session.preflight.targetAccount,
            snapshot: nil,
            phases: session.phases + [.verifying, .failed],
            message: message
        )
    }

    public func switchAccount(
        targetAccountID: UUID,
        reason: SwitchReason = .userRequested,
        userConfirmed: Bool,
        officialFlowConfirmedByUser: Bool,
        refreshSnapshot: @escaping @Sendable (Account) async throws -> QuotaSnapshot?
    ) async -> SwitchOutcome {
        do {
            let preflight = try preflight(targetAccountID: targetAccountID, reason: reason)
            guard userConfirmed else {
                let message = "用户未确认切换到：\(preflight.targetAccount.alias)"
                try? recordFinalEvent(
                    preflight: preflight,
                    result: .cancelled,
                    message: message,
                    providerName: provider.providerName,
                    createdAt: now()
                )
                return SwitchOutcome(
                    result: .cancelled,
                    targetAccount: preflight.targetAccount,
                    snapshot: nil,
                    phases: [.preflight, .confirmation, .cancelled],
                    message: message
                )
            }
            let session = try await launch(preflight)
            return await complete(
                session,
                officialFlowConfirmedByUser: officialFlowConfirmedByUser,
                refreshSnapshot: refreshSnapshot
            )
        } catch {
            return SwitchOutcome(
                result: .failed,
                targetAccount: nil,
                snapshot: nil,
                phases: [.preflight, .failed],
                message: "切换前检查失败：\(error.localizedDescription)"
            )
        }
    }

    private func warnings(for target: Account, targetSnapshot: QuotaSnapshot?) -> [SwitchPreflightWarning] {
        var warnings: [SwitchPreflightWarning] = []
        if target.authStatus == .unknown {
            warnings.append(.authorizationUnknown)
        }
        if !target.verificationMethods.isEmpty {
            warnings.append(.additionalVerificationRequired)
        }
        guard let targetSnapshot else {
            warnings.append(.snapshotMissing)
            return warnings
        }
        if targetSnapshot.confidence == .stale
            || targetSnapshot.confidence == .failed
            || now().timeIntervalSince(targetSnapshot.capturedAt) > snapshotStaleInterval {
            warnings.append(.snapshotStale)
        }
        return warnings
    }

    private func markTargetSwitched(_ account: Account) throws -> Account {
        var updated = account
        updated.lastSwitchedAt = now()
        if updated.authStatus == .unknown {
            updated.authStatus = .active
        }
        try accountRepository.upsert(updated)
        return updated
    }

    private func saveStaleSnapshot(for account: Account) throws -> QuotaSnapshot {
        let snapshot = QuotaSnapshot(
            accountAlias: account.alias,
            capturedAt: now(),
            fiveHourRemainingPercent: nil,
            weeklyRemainingPercent: nil,
            confidence: .stale
        )
        try snapshotRepository.save(snapshot)
        return snapshot
    }

    private func recordFinalEvent(
        preflight: SwitchPreflight,
        result: SwitchEventResult,
        message: String,
        providerName: String,
        createdAt: Date
    ) throws {
        let event = SwitchEvent(
            fromAccountID: preflight.fromAccount?.id,
            fromAccountAlias: preflight.fromAccount?.alias ?? preflight.currentSnapshot?.accountAlias,
            toAccountID: preflight.targetAccount.id,
            toAccountAlias: preflight.targetAccount.alias,
            reason: preflight.reason,
            providerName: providerName,
            result: result,
            message: message,
            createdAt: createdAt
        )
        try switchEventRepository.record(event)
        try auditRepository.record(
            AuditEvent(
                eventType: .switchAccount,
                objectType: "account",
                objectID: preflight.targetAccount.id.uuidString,
                result: auditResult(for: result),
                message: message,
                createdAt: createdAt
            )
        )
    }

    private func auditResult(for result: SwitchEventResult) -> AuditResult {
        switch result {
        case .success, .staleSucceeded:
            return .success
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }
}
