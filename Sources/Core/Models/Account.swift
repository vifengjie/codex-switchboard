import Foundation

public struct Account: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var alias: String
    public var workspaceName: String?
    public var emailMasked: String?
    public var planType: PlanType
    public var authStatus: AuthStatus
    public var enabled: Bool
    public var priority: Int

    public init(
        id: UUID = UUID(),
        alias: String,
        workspaceName: String? = nil,
        emailMasked: String? = nil,
        planType: PlanType = .unknown,
        authStatus: AuthStatus = .unknown,
        enabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.alias = alias
        self.workspaceName = workspaceName
        self.emailMasked = emailMasked
        self.planType = planType
        self.authStatus = authStatus
        self.enabled = enabled
        self.priority = priority
    }
}

public enum PlanType: String, Sendable {
    case plus
    case business
    case enterprise
    case unknown
}

public enum AuthStatus: String, Sendable {
    case active
    case expired
    case revoked
    case unknown
}
