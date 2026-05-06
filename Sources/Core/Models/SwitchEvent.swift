import Foundation

public struct SwitchEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var fromAccountID: UUID?
    public var fromAccountAlias: String?
    public var toAccountID: UUID
    public var toAccountAlias: String
    public var reason: SwitchReason
    public var providerName: String
    public var result: SwitchEventResult
    public var message: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        fromAccountID: UUID? = nil,
        fromAccountAlias: String? = nil,
        toAccountID: UUID,
        toAccountAlias: String,
        reason: SwitchReason,
        providerName: String,
        result: SwitchEventResult,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromAccountID = fromAccountID
        self.fromAccountAlias = fromAccountAlias
        self.toAccountID = toAccountID
        self.toAccountAlias = toAccountAlias
        self.reason = reason
        self.providerName = providerName
        self.result = result
        self.message = message
        self.createdAt = createdAt
    }
}

public enum SwitchReason: String, Sendable {
    case userRequested = "user_requested"
    case recommendation
    case manual
}

public enum SwitchEventResult: String, Sendable {
    case success
    case staleSucceeded = "stale_succeeded"
    case failed
    case cancelled
}

public enum SwitchPhase: String, Sendable {
    case idle
    case preflight
    case confirmation
    case launching
    case waitingOfficialFlow = "waiting_official_flow"
    case verifying
    case refreshing
    case succeeded
    case staleSucceeded = "stale_succeeded"
    case failed
    case cancelled
}
