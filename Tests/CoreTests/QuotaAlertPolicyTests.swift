import CodexQuotaCore
import XCTest

final class QuotaAlertPolicyTests: XCTestCase {
    func testAlertPolicyClassifiesThresholdStates() {
        let policy = QuotaAlertPolicy()
        let settings = AppSettings.default
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(policy.status(for: snapshot(fiveHour: 80, weekly: 80, now: now), settings: settings, now: now), .normal)
        XCTAssertEqual(policy.status(for: snapshot(fiveHour: 20, weekly: 80, now: now), settings: settings, now: now), .warning)
        XCTAssertEqual(policy.status(for: snapshot(fiveHour: 15, weekly: 80, now: now), settings: settings, now: now), .fiveHourRisk)
        XCTAssertEqual(policy.status(for: snapshot(fiveHour: 20, weekly: 5, now: now), settings: settings, now: now), .weeklyCritical)
        XCTAssertEqual(policy.status(for: snapshot(fiveHour: 5, weekly: 80, now: now), settings: settings, now: now), .executionRisk)
        XCTAssertEqual(policy.status(for: snapshot(fiveHour: nil, weekly: 80, now: now), settings: settings, now: now), .unavailable)
    }

    func testAlertPolicyMarksStaleSnapshots() {
        let policy = QuotaAlertPolicy()
        let settings = AppSettings(snapshotStaleMinutes: 15)
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        let snapshot = QuotaSnapshot(
            accountAlias: "主账号",
            capturedAt: capturedAt,
            fiveHourRemainingPercent: 80,
            weeklyRemainingPercent: 80,
            confidence: .observed
        )

        XCTAssertEqual(policy.status(for: snapshot, settings: settings, now: now), .stale)
    }

    func testNotificationRequestAndDedupeWindow() throws {
        let policy = QuotaAlertPolicy()
        let settings = AppSettings(notificationDedupeMinutes: 30)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try XCTUnwrap(
            policy.notificationRequest(
                for: snapshot(fiveHour: 10, weekly: 80, now: now),
                settings: settings,
                now: now
            )
        )

        XCTAssertEqual(request.status, .fiveHourRisk)
        XCTAssertEqual(request.dedupeKey, "主账号|five_hour_risk")
        XCTAssertTrue(policy.shouldSuppress(lastDeliveredAt: Date(timeIntervalSince1970: 900), settings: settings, now: now))
        XCTAssertFalse(policy.shouldSuppress(lastDeliveredAt: Date(timeIntervalSince1970: -1_000), settings: settings, now: now))
    }

    private func snapshot(fiveHour: Double?, weekly: Double?, now: Date) -> QuotaSnapshot {
        QuotaSnapshot(
            accountAlias: "主账号",
            capturedAt: now,
            fiveHourRemainingPercent: fiveHour,
            weeklyRemainingPercent: weekly,
            confidence: .observed
        )
    }
}
