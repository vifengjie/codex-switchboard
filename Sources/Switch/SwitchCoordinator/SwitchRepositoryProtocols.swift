import CodexQuotaCore
import CodexQuotaStorage
import Foundation

public protocol SwitchAccountRepository: Sendable {
    func listAccounts() throws -> [Account]
    func account(id: UUID) throws -> Account?
    func upsert(_ account: Account) throws
    func delete(id: UUID) throws
}

public protocol SwitchSnapshotRepository: Sendable {
    func latestSnapshot() throws -> QuotaSnapshot?
    func latestSnapshot(accountAlias: String) throws -> QuotaSnapshot?
    func save(_ snapshot: QuotaSnapshot) throws
}

public protocol SwitchEventRepository: Sendable {
    func record(_ event: SwitchEvent) throws
    func recent(limit: Int) throws -> [SwitchEvent]
}

public protocol SwitchAuditRepository: Sendable {
    func record(_ event: AuditEvent) throws
}

extension SQLiteAccountRepository: SwitchAccountRepository {}
extension SQLiteSnapshotRepository: SwitchSnapshotRepository {}
extension SQLiteSwitchEventRepository: SwitchEventRepository {}
extension SQLiteAuditRepository: SwitchAuditRepository {}
