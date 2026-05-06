import Foundation

public struct RecommendedAccount: Equatable, Sendable {
    public var account: Account
    public var score: Double
    public var reason: String

    public init(account: Account, score: Double, reason: String) {
        self.account = account
        self.score = score
        self.reason = reason
    }
}

public struct RecommendationEngine: Sendable {
    public init() {}

    public func recommend(accounts: [Account]) -> RecommendedAccount? {
        accounts
            .filter { $0.enabled && $0.authStatus != .expired && $0.authStatus != .revoked }
            .map { account in
                RecommendedAccount(
                    account: account,
                    score: Double(account.priority),
                    reason: "优先级 \(account.priority)"
                )
            }
            .max { left, right in
                left.score < right.score
            }
    }
}
