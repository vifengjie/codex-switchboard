import CodexQuotaCore
import XCTest

final class RecommendationEngineTests: XCTestCase {
    func testRecommendationSkipsDisabledExpiredAndRevokedAccounts() {
        let active = Account(alias: "active", authStatus: .active, enabled: true, priority: 1)
        let disabled = Account(alias: "disabled", authStatus: .active, enabled: false, priority: 100)
        let expired = Account(alias: "expired", authStatus: .expired, enabled: true, priority: 100)
        let revoked = Account(alias: "revoked", authStatus: .revoked, enabled: true, priority: 100)

        let recommended = RecommendationEngine().recommend(accounts: [active, disabled, expired, revoked])

        XCTAssertEqual(recommended?.account.alias, "active")
    }

    func testRecommendationScoresQuotaForLowFiveHourReason() {
        let lowPriorityHealthy = Account(alias: "healthy", authStatus: .active, priority: 1)
        let highPriorityLow = Account(alias: "low", authStatus: .active, priority: 20)
        let snapshots = [
            "healthy": QuotaSnapshot(
                accountAlias: "healthy",
                fiveHourRemainingPercent: 90,
                weeklyRemainingPercent: 90,
                confidence: .observed
            ),
            "low": QuotaSnapshot(
                accountAlias: "low",
                fiveHourRemainingPercent: 5,
                weeklyRemainingPercent: 90,
                confidence: .observed
            )
        ]

        let recommended = RecommendationEngine().recommend(
            accounts: [highPriorityLow, lowPriorityHealthy],
            snapshotsByAccountAlias: snapshots,
            reason: .lowFiveHourQuota
        )

        XCTAssertEqual(recommended?.account.alias, "healthy")
        XCTAssertEqual(recommended?.score, 91)
    }
}
