import CodexQuotaCore
import Foundation

public enum AccountManagerError: Error, Equatable, Sendable {
    case accountNotFound(UUID)
}

public struct AccountManager: Sendable {
    private let accountRepository: any SwitchAccountRepository
    private let auditRepository: any SwitchAuditRepository

    public init(
        accountRepository: any SwitchAccountRepository,
        auditRepository: any SwitchAuditRepository
    ) {
        self.accountRepository = accountRepository
        self.auditRepository = auditRepository
    }

    public func addAccount(
        alias: String,
        provider: AccountProvider = .unknown,
        workspaceName: String? = nil,
        emailMasked: String? = nil,
        planType: PlanType = .unknown,
        seatType: SeatType = .unknown,
        authMethod: AuthMethod = .unknown,
        authStatus: AuthStatus = .unknown,
        keychainRef: String? = nil,
        enabled: Bool = true,
        priority: Int = 0
    ) throws -> Account {
        let account = Account(
            alias: alias,
            provider: provider,
            workspaceName: workspaceName,
            emailMasked: emailMasked,
            planType: planType,
            seatType: seatType,
            authMethod: authMethod,
            authStatus: authStatus,
            keychainRef: keychainRef,
            enabled: enabled,
            priority: priority
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
        return account
    }

    @discardableResult
    public func saveAccount(_ account: Account, message: String? = nil) throws -> Account {
        try accountRepository.upsert(account)
        try auditRepository.record(
            AuditEvent(
                eventType: .accountUpdate,
                objectType: "account",
                objectID: account.id.uuidString,
                result: .success,
                message: message ?? "更新账号：\(account.alias)"
            )
        )
        return account
    }

    @discardableResult
    public func setEnabled(accountID: UUID, enabled: Bool) throws -> Account {
        var account = try requireAccount(id: accountID)
        account.enabled = enabled
        return try saveAccount(
            account,
            message: "\(enabled ? "启用" : "禁用")账号：\(account.alias)"
        )
    }

    @discardableResult
    public func setPriority(accountID: UUID, priority: Int) throws -> Account {
        var account = try requireAccount(id: accountID)
        account.priority = priority
        return try saveAccount(account, message: "更新账号优先级：\(account.alias) -> \(priority)")
    }

    @discardableResult
    public func updateAuthStatus(accountID: UUID, authStatus: AuthStatus) throws -> Account {
        var account = try requireAccount(id: accountID)
        account.authStatus = authStatus
        return try saveAccount(account, message: "更新账号授权状态：\(account.alias) -> \(authStatus.rawValue)")
    }

    public func deleteAccount(accountID: UUID) throws {
        let account = try requireAccount(id: accountID)
        try accountRepository.delete(id: accountID)
        try auditRepository.record(
            AuditEvent(
                eventType: .accountDelete,
                objectType: "account",
                objectID: account.id.uuidString,
                result: .success,
                message: "删除账号：\(account.alias)"
            )
        )
    }

    private func requireAccount(id: UUID) throws -> Account {
        guard let account = try accountRepository.account(id: id) else {
            throw AccountManagerError.accountNotFound(id)
        }
        return account
    }
}
