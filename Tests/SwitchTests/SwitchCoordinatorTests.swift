import CodexQuotaCore
import CodexQuotaStorage
import CodexQuotaSwitch
import Foundation
import XCTest

final class SwitchCoordinatorTests: XCTestCase {
    func testPreflightRejectsDisabledExpiredRevokedAndCooldownTargets() throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_000))
        let disabled = Account(alias: "disabled", authStatus: .active, enabled: false)
        let expired = Account(alias: "expired", authStatus: .expired)
        let revoked = Account(alias: "revoked", authStatus: .revoked)
        let cooling = Account(
            alias: "cooling",
            authStatus: .active,
            lastSwitchedAt: Date(timeIntervalSince1970: 950)
        )
        try fixture.accounts.upsert(disabled)
        try fixture.accounts.upsert(expired)
        try fixture.accounts.upsert(revoked)
        try fixture.accounts.upsert(cooling)

        XCTAssertThrowsError(try fixture.coordinator.preflight(targetAccountID: disabled.id)) { error in
            XCTAssertEqual(error as? SwitchPreflightError, .targetDisabled("disabled"))
        }
        XCTAssertThrowsError(try fixture.coordinator.preflight(targetAccountID: expired.id)) { error in
            XCTAssertEqual(error as? SwitchPreflightError, .authorizationExpired("expired"))
        }
        XCTAssertThrowsError(try fixture.coordinator.preflight(targetAccountID: revoked.id)) { error in
            XCTAssertEqual(error as? SwitchPreflightError, .authorizationRevoked("revoked"))
        }
        XCTAssertThrowsError(try fixture.coordinator.preflight(targetAccountID: cooling.id)) { error in
            XCTAssertEqual(error as? SwitchPreflightError, .cooldownActive("cooling", remainingSeconds: 250))
        }
    }

    func testPreflightAllowsUnknownAuthWithMissingSnapshotWarning() throws {
        let fixture = try makeFixture()
        let target = Account(alias: "target", authStatus: .unknown)
        try fixture.accounts.upsert(target)

        let preflight = try fixture.coordinator.preflight(targetAccountID: target.id)

        XCTAssertEqual(preflight.targetAccount.id, target.id)
        XCTAssertEqual(preflight.warnings, [.authorizationUnknown, .snapshotMissing])
        XCTAssertEqual(preflight.privacyNotice.contains("不会读取、复制或替换 Codex auth 文件"), true)
    }

    func testPreflightWarnsWhenAdditionalVerificationIsRequired() throws {
        let fixture = try makeFixture()
        let target = Account(
            alias: "target",
            authStatus: .active,
            verificationMethods: [.emailOTP, .authenticatorTOTP],
            verificationHint: "邮箱验证码 + Google Authenticator"
        )
        try fixture.accounts.upsert(target)

        let preflight = try fixture.coordinator.preflight(targetAccountID: target.id)

        XCTAssertEqual(preflight.warnings, [.additionalVerificationRequired, .snapshotMissing])
        XCTAssertEqual(preflight.targetAccount.verificationMethods, [.emailOTP, .authenticatorTOTP])
        XCTAssertEqual(preflight.targetAccount.verificationHint, "邮箱验证码 + Google Authenticator")
    }

    func testSwitchCancellationWritesSwitchAndAuditEvents() async throws {
        let fixture = try makeFixture()
        let target = Account(alias: "target", authStatus: .active)
        try fixture.accounts.upsert(target)

        let outcome = await fixture.coordinator.switchAccount(
            targetAccountID: target.id,
            userConfirmed: false,
            officialFlowConfirmedByUser: false,
            refreshSnapshot: { _ in nil }
        )

        XCTAssertEqual(outcome.result, .cancelled)
        XCTAssertEqual(outcome.phases, [.preflight, .confirmation, .cancelled])
        XCTAssertEqual(try fixture.switchEvents.recent(limit: 10).first?.result, .cancelled)
        XCTAssertEqual(try fixture.audits.recent(limit: 10).first?.result, .cancelled)
    }

    func testSwitchSuccessLaunchesProviderRefreshesSnapshotAndAudits() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let fixture = try makeFixture(now: now)
        let target = Account(alias: "target", authStatus: .unknown)
        try fixture.accounts.upsert(target)

        let outcome = await fixture.coordinator.switchAccount(
            targetAccountID: target.id,
            userConfirmed: true,
            officialFlowConfirmedByUser: true,
            refreshSnapshot: { account in
                QuotaSnapshot(
                    accountAlias: account.alias,
                    capturedAt: now,
                    fiveHourRemainingPercent: 72,
                    weeklyRemainingPercent: 88,
                    confidence: .observed
                )
            }
        )

        XCTAssertEqual(outcome.result, .success)
        XCTAssertEqual(outcome.phases, [.preflight, .confirmation, .launching, .waitingOfficialFlow, .verifying, .refreshing, .succeeded])
        XCTAssertEqual(outcome.snapshot?.accountAlias, "target")
        XCTAssertEqual(outcome.snapshot?.fiveHourRemainingPercent, 72)
        let updatedTarget = try XCTUnwrap(fixture.accounts.account(id: target.id))
        XCTAssertEqual(updatedTarget.authStatus, .active)
        XCTAssertEqual(updatedTarget.lastSwitchedAt, now)
        XCTAssertEqual(try fixture.snapshots.latestSnapshot(accountAlias: "target")?.weeklyRemainingPercent, 88)
        XCTAssertEqual(try fixture.switchEvents.recent(limit: 10).first?.result, .success)
        XCTAssertEqual(try fixture.audits.recent(limit: 10).first?.eventType, .switchAccount)
    }

    func testRefreshFailureCreatesStaleSnapshotForTarget() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let fixture = try makeFixture(now: now)
        let target = Account(alias: "target", authStatus: .active)
        try fixture.accounts.upsert(target)

        let outcome = await fixture.coordinator.switchAccount(
            targetAccountID: target.id,
            userConfirmed: true,
            officialFlowConfirmedByUser: true,
            refreshSnapshot: { _ in
                throw CocoaError(.fileReadUnknown)
            }
        )

        XCTAssertEqual(outcome.result, .staleSucceeded)
        XCTAssertEqual(outcome.phases.last, .staleSucceeded)
        XCTAssertEqual(outcome.snapshot?.accountAlias, "target")
        XCTAssertEqual(outcome.snapshot?.confidence, .stale)
        XCTAssertNil(outcome.snapshot?.fiveHourRemainingPercent)
        XCTAssertEqual(try fixture.snapshots.latestSnapshot(accountAlias: "target")?.confidence, .stale)
        XCTAssertEqual(try fixture.switchEvents.recent(limit: 10).first?.result, .staleSucceeded)
    }

    func testAwaitCompletionPollsUntilProviderReportsLoggedIn() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let provider = PollingMockSwitchProvider(succeedsOnAttempt: 3)
        let fixture = try makeFixture(now: now, provider: provider)
        let target = Account(alias: "target", authStatus: .active)
        try fixture.accounts.upsert(target)

        let preflight = try fixture.coordinator.preflight(targetAccountID: target.id)
        let session = try await fixture.coordinator.launch(preflight)
        let outcome = await fixture.coordinator.awaitCompletion(
            session,
            timeoutSeconds: 5,
            pollIntervalSeconds: 0.01,
            refreshSnapshot: { account in
                QuotaSnapshot(
                    accountAlias: account.alias,
                    capturedAt: now,
                    fiveHourRemainingPercent: 61,
                    weeklyRemainingPercent: 82,
                    confidence: .observed
                )
            }
        )

        XCTAssertEqual(outcome.result, .success)
        XCTAssertEqual(outcome.snapshot?.fiveHourRemainingPercent, 61)
    }

    private func makeFixture(
        now: Date = Date(timeIntervalSince1970: 1_000),
        provider: any SwitchProvider = MockSwitchProvider()
    ) throws -> Fixture {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let accounts = SQLiteAccountRepository(store: store)
        let snapshots = SQLiteSnapshotRepository(store: store)
        let switchEvents = SQLiteSwitchEventRepository(store: store)
        let audits = SQLiteAuditRepository(store: store)
        let coordinator = SwitchCoordinator(
            accountRepository: accounts,
            snapshotRepository: snapshots,
            switchEventRepository: switchEvents,
            auditRepository: audits,
            provider: provider,
            now: { now }
        )
        return Fixture(
            accounts: accounts,
            snapshots: snapshots,
            switchEvents: switchEvents,
            audits: audits,
            coordinator: coordinator
        )
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-quota-manager-\(UUID().uuidString)")
            .appendingPathComponent("quota-manager.sqlite")
    }
}

private struct Fixture {
    var accounts: SQLiteAccountRepository
    var snapshots: SQLiteSnapshotRepository
    var switchEvents: SQLiteSwitchEventRepository
    var audits: SQLiteAuditRepository
    var coordinator: SwitchCoordinator
}

private struct MockSwitchProvider: SwitchProvider {
    var providerName = "mock_provider"

    func launchSwitchFlow(from source: Account?, to target: Account) async throws -> SwitchProviderLaunch {
        SwitchProviderLaunch(
            providerName: providerName,
            openedExternalFlow: true,
            instructions: ["mock launch \(target.alias)"]
        )
    }

    func verifySwitch(to target: Account, userConfirmedOfficialFlow: Bool) async throws -> SwitchVerification {
        SwitchVerification(
            verified: userConfirmedOfficialFlow,
            message: userConfirmedOfficialFlow ? "verified \(target.alias)" : "not verified"
        )
    }
}

private actor PollingVerifierState {
    private var attempts = 0
    let succeedsOnAttempt: Int

    init(succeedsOnAttempt: Int) {
        self.succeedsOnAttempt = succeedsOnAttempt
    }

    func nextAttemptVerified() -> Bool {
        attempts += 1
        return attempts >= succeedsOnAttempt
    }
}

private struct PollingMockSwitchProvider: SwitchProvider {
    var providerName = "polling_mock_provider"
    private let state: PollingVerifierState

    init(succeedsOnAttempt: Int) {
        self.state = PollingVerifierState(succeedsOnAttempt: succeedsOnAttempt)
    }

    func launchSwitchFlow(from source: Account?, to target: Account) async throws -> SwitchProviderLaunch {
        SwitchProviderLaunch(
            providerName: providerName,
            openedExternalFlow: true,
            instructions: ["polling launch \(target.alias)"]
        )
    }

    func verifySwitch(to target: Account, userConfirmedOfficialFlow: Bool) async throws -> SwitchVerification {
        let verified = await state.nextAttemptVerified()
        return SwitchVerification(
            verified: verified,
            message: verified ? "verified \(target.alias)" : "waiting"
        )
    }
}
