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
        recommend(accounts: accounts, snapshotsByAccountAlias: [:], reason: .manual)
    }

    public func recommend(
        accounts: [Account],
        snapshotsByAccountAlias: [String: QuotaSnapshot],
        reason: RecommendationReason
    ) -> RecommendedAccount? {
        accounts
            .filter(isEligible(_:))
            .map { account in
                let snapshot = snapshotsByAccountAlias[account.alias]
                let quotaScore = quotaScore(snapshot: snapshot, reason: reason)
                let score = Double(account.priority) + quotaScore
                return RecommendedAccount(
                    account: account,
                    score: score,
                    reason: recommendationReason(account: account, snapshot: snapshot, reason: reason)
                )
            }
            .max { left, right in
                left.score < right.score
            }
    }

    private func isEligible(_ account: Account) -> Bool {
        account.enabled && account.authStatus != .expired && account.authStatus != .revoked
    }

    private func quotaScore(snapshot: QuotaSnapshot?, reason: RecommendationReason) -> Double {
        guard let snapshot else {
            return 0
        }
        switch reason {
        case .lowFiveHourQuota:
            return snapshot.fiveHourRemainingPercent ?? 0
        case .lowWeeklyQuota:
            return snapshot.weeklyRemainingPercent ?? 0
        case .manual:
            return ((snapshot.fiveHourRemainingPercent ?? 0) + (snapshot.weeklyRemainingPercent ?? 0)) / 2
        }
    }

    private func recommendationReason(
        account: Account,
        snapshot: QuotaSnapshot?,
        reason: RecommendationReason
    ) -> String {
        guard let snapshot else {
            return "优先级 \(account.priority)，暂无额度快照"
        }

        switch reason {
        case .lowFiveHourQuota:
            return "优先级 \(account.priority)，5H 剩余 \(formatPercent(snapshot.fiveHourRemainingPercent))"
        case .lowWeeklyQuota:
            return "优先级 \(account.priority)，1W 剩余 \(formatPercent(snapshot.weeklyRemainingPercent))"
        case .manual:
            return "优先级 \(account.priority)，5H \(formatPercent(snapshot.fiveHourRemainingPercent)) / 1W \(formatPercent(snapshot.weeklyRemainingPercent))"
        }
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded()))%"
    }
}

public enum RecommendationReason: String, Sendable {
    case lowFiveHourQuota = "low_5h_quota"
    case lowWeeklyQuota = "low_weekly_quota"
    case manual
}
