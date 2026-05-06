import Foundation

public struct Account: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var alias: String
    public var provider: AccountProvider
    public var workspaceName: String?
    public var emailMasked: String?
    public var planType: PlanType
    public var seatType: SeatType
    public var authMethod: AuthMethod
    public var authStatus: AuthStatus
    public var keychainRef: String?
    public var enabled: Bool
    public var priority: Int
    public var lastSwitchedAt: Date?

    public init(
        id: UUID = UUID(),
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
        priority: Int = 0,
        lastSwitchedAt: Date? = nil
    ) {
        self.id = id
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
}

public enum AccountProvider: String, CaseIterable, Sendable {
    case openai
    case chatgpt
    case unknown
}

public enum PlanType: String, CaseIterable, Sendable {
    case plus
    case business
    case enterprise
    case unknown
}

public enum SeatType: String, CaseIterable, Sendable {
    case standard
    case codex
    case unknown
}

public enum AuthMethod: String, CaseIterable, Sendable {
    case chatgpt
    case apiKey = "api_key"
    case unknown
}

public enum AuthStatus: String, CaseIterable, Sendable {
    case active
    case expired
    case revoked
    case unknown
}
