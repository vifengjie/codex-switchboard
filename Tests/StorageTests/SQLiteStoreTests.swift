import CodexQuotaCore
import CodexQuotaStorage
import Foundation
import XCTest

final class SQLiteStoreTests: XCTestCase {
    func testSQLiteStoreMigrationCreatesDatabase() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())

        try store.migrate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))
    }

    func testSettingsRepositoryPersistsDefaults() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteSettingsRepository(store: store)

        let settings = try repository.ensureDefaultSettings()
        let loaded = try repository.load()

        XCTAssertEqual(settings, .default)
        XCTAssertEqual(loaded, .default)
    }

    func testSettingsRepositoryPersistsUpdates() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteSettingsRepository(store: store)
        let updated = AppSettings(
            fiveHourRiskThresholdPercent: 20,
            weeklyCriticalThresholdPercent: 8,
            notificationDedupeMinutes: 45,
            snapshotStaleMinutes: 25,
            redactWorkspaceNames: false,
            redactThreadTitles: true
        )

        try repository.save(updated)
        let loaded = try repository.load()

        XCTAssertEqual(loaded, updated)
    }

    func testAccountRepositoryPersistsAndListsAccounts() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteAccountRepository(store: store)
        let lowPriority = Account(
            alias: "备用账号",
            workspaceName: "Business-B",
            emailMasked: "b***@example.com",
            planType: .business,
            authStatus: .active,
            enabled: true,
            priority: 1
        )
        let highPriority = Account(
            alias: "主账号",
            provider: .chatgpt,
            workspaceName: "Business-A",
            emailMasked: "a***@example.com",
            loginIdentifierMasked: "owner@example.com",
            planType: .business,
            seatType: .codex,
            authMethod: .chatgpt,
            authStatus: .active,
            passwordRequired: true,
            verificationMethods: [.emailOTP, .authenticatorTOTP],
            verificationHint: "邮箱验证码 + Google Authenticator",
            keychainRef: "codex-quota-manager.account.primary",
            enabled: true,
            priority: 10,
            lastSwitchedAt: Date(timeIntervalSince1970: 300)
        )

        try repository.upsert(lowPriority)
        try repository.upsert(highPriority)
        let accounts = try repository.listAccounts()

        XCTAssertEqual(accounts.map(\.alias), ["主账号", "备用账号"])
        XCTAssertEqual(accounts.first?.workspaceName, "Business-A")
        XCTAssertEqual(accounts.first?.emailMasked, "a***@example.com")
        XCTAssertEqual(accounts.first?.loginIdentifierMasked, "owner@example.com")
        XCTAssertEqual(accounts.first?.provider, .chatgpt)
        XCTAssertEqual(accounts.first?.planType, .business)
        XCTAssertEqual(accounts.first?.seatType, .codex)
        XCTAssertEqual(accounts.first?.authMethod, .chatgpt)
        XCTAssertEqual(accounts.first?.authStatus, .active)
        XCTAssertEqual(accounts.first?.passwordRequired, true)
        XCTAssertEqual(accounts.first?.verificationMethods, [.emailOTP, .authenticatorTOTP])
        XCTAssertEqual(accounts.first?.verificationHint, "邮箱验证码 + Google Authenticator")
        XCTAssertEqual(accounts.first?.keychainRef, "codex-quota-manager.account.primary")
        XCTAssertEqual(accounts.first?.lastSwitchedAt?.timeIntervalSince1970, 300)
    }

    func testAccountRepositoryUpdatesAndDeletesAccount() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteAccountRepository(store: store)
        let id = UUID()
        let initial = Account(id: id, alias: "旧账号", enabled: true, priority: 0)
        let updated = Account(
            id: id,
            alias: "新账号",
            planType: .plus,
            authStatus: .expired,
            enabled: false,
            priority: 5
        )

        try repository.upsert(initial)
        try repository.upsert(updated)
        let loaded = try repository.account(id: id)

        XCTAssertEqual(loaded?.alias, "新账号")
        XCTAssertEqual(loaded?.planType, .plus)
        XCTAssertEqual(loaded?.authStatus, .expired)
        XCTAssertEqual(loaded?.enabled, false)
        XCTAssertEqual(loaded?.priority, 5)

        try repository.delete(id: id)
        XCTAssertNil(try repository.account(id: id))
    }

    func testKeychainStoreSavesReadsAndDeletesSecrets() throws {
        let keychain = KeychainStore(defaultService: "CodexQuotaManagerTests.\(UUID().uuidString)")
        let reference = keychain.accountReference(accountID: UUID())
        let secret = Data("secret-token".utf8)
        defer {
            _ = try? keychain.deleteSecret(reference: reference)
        }

        do {
            try keychain.saveSecret(secret, reference: reference)
            XCTAssertEqual(try keychain.readSecret(reference: reference), secret)
            XCTAssertTrue(try keychain.deleteSecret(reference: reference))
            XCTAssertNil(try keychain.readSecret(reference: reference))
        } catch {
            throw XCTSkip("Keychain unavailable in this test environment: \(error)")
        }
    }

    func testAuditRepositoryRecordsRecentEvents() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteAuditRepository(store: store)
        let older = AuditEvent(
            id: UUID(),
            eventType: .accountCreate,
            actorName: "tester",
            objectType: "account",
            objectID: "account-1",
            result: .success,
            message: "older",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = AuditEvent(
            id: UUID(),
            eventType: .accountDelete,
            actorName: "tester",
            objectType: "account",
            objectID: "account-1",
            result: .success,
            message: "newer",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try repository.record(older)
        try repository.record(newer)
        let events = try repository.recent(limit: 10)

        XCTAssertEqual(events.map(\.message), ["newer", "older"])
        XCTAssertEqual(events.first?.eventType, .accountDelete)
        XCTAssertEqual(events.first?.actorName, "tester")
        XCTAssertEqual(events.first?.objectType, "account")
        XCTAssertEqual(events.first?.objectID, "account-1")
        XCTAssertEqual(events.first?.result, .success)
    }

    func testAuditRepositoryHonorsLimit() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteAuditRepository(store: store)

        try repository.record(AuditEvent(eventType: .accountCreate, result: .success, message: "1"))
        try repository.record(AuditEvent(eventType: .accountUpdate, result: .success, message: "2"))

        XCTAssertEqual(try repository.recent(limit: 1).count, 1)
    }

    func testAuditRepositoryFiltersByTypeResultAndQuery() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteAuditRepository(store: store)

        try repository.record(
            AuditEvent(
                eventType: .export,
                actorName: "tester",
                objectType: "usage_events",
                objectID: "csv",
                result: .success,
                message: "导出 usage csv"
            )
        )
        try repository.record(
            AuditEvent(
                eventType: .cleanup,
                actorName: "tester",
                objectType: "storage",
                objectID: "local",
                result: .failed,
                message: "cleanup failed"
            )
        )

        let filtered = try repository.query(
            AuditEventFilter(
                eventType: .export,
                result: .success,
                query: "usage",
                limit: 20
            )
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.eventType, .export)
        XCTAssertEqual(filtered.first?.result, .success)
        XCTAssertEqual(filtered.first?.objectType, "usage_events")
    }

    func testUsageEventRepositoryPersistsRecentEvents() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteUsageEventRepository(store: store)
        let older = UsageEvent(
            accountAlias: "主账号",
            threadID: "thread-1",
            taskTitleMasked: "older task",
            eventTime: Date(timeIntervalSince1970: 100),
            model: "mock-codex",
            inputTokensDelta: 1_000_000,
            cachedInputTokensDelta: 500_000,
            outputTokensDelta: 250_000,
            reasoningOutputTokensDelta: 125_000,
            estimatedCreditsDelta: 12.5,
            rateCardVersion: "fixture-1",
            source: .localJSONL
        )
        let newer = UsageEvent(
            accountAlias: "备用账号",
            threadID: "thread-2",
            taskTitleMasked: "newer task",
            eventTime: Date(timeIntervalSince1970: 200),
            model: "mock-codex",
            inputTokensDelta: 2_000_000,
            cachedInputTokensDelta: 1_000_000,
            outputTokensDelta: 500_000,
            reasoningOutputTokensDelta: 250_000,
            estimatedCreditsDelta: 25,
            rateCardVersion: "fixture-1",
            source: .importedReport
        )

        try repository.save(older)
        try repository.save(newer)
        let events = try repository.recent(limit: 10)

        XCTAssertEqual(events.map(\.taskTitleMasked), ["newer task", "older task"])
        XCTAssertEqual(events.first?.accountAlias, "备用账号")
        XCTAssertEqual(events.first?.threadID, "thread-2")
        XCTAssertEqual(events.first?.model, "mock-codex")
        XCTAssertEqual(events.first?.inputTokensDelta, 2_000_000)
        XCTAssertEqual(events.first?.cachedInputTokensDelta, 1_000_000)
        XCTAssertEqual(events.first?.outputTokensDelta, 500_000)
        XCTAssertEqual(events.first?.reasoningOutputTokensDelta, 250_000)
        XCTAssertEqual(events.first?.estimatedCreditsDelta, 25)
        XCTAssertEqual(events.first?.rateCardVersion, "fixture-1")
        XCTAssertEqual(events.first?.source, .importedReport)
    }

    func testUsageEventRepositoryUpsertsAndHonorsLimit() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteUsageEventRepository(store: store)
        let id = UUID()
        let initial = UsageEvent(
            id: id,
            eventTime: Date(timeIntervalSince1970: 100),
            inputTokensDelta: 1,
            source: .manual
        )
        let updated = UsageEvent(
            id: id,
            accountAlias: "updated",
            eventTime: Date(timeIntervalSince1970: 300),
            inputTokensDelta: 2_000_000,
            source: .localJSONL
        )
        let other = UsageEvent(
            eventTime: Date(timeIntervalSince1970: 200),
            inputTokensDelta: 1_000_000,
            source: .manual
        )

        try repository.save(initial)
        try repository.save(updated)
        try repository.save(other)
        let events = try repository.recent(limit: 1)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, id)
        XCTAssertEqual(events.first?.accountAlias, "updated")
        XCTAssertEqual(events.first?.inputMTokensDelta, 2)
        XCTAssertEqual(events.first?.source, .localJSONL)
    }

    func testUsageEventRepositoryFiltersByAccountModelThreadSourceAndTime() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteUsageEventRepository(store: store)
        let matching = UsageEvent(
            accountAlias: "主账号",
            threadID: "thread-abc",
            taskTitleMasked: "quota investigate",
            eventTime: Date(timeIntervalSince1970: 500),
            model: "gpt-5",
            inputTokensDelta: 1_000_000,
            source: .localJSONL
        )
        let differentAccount = UsageEvent(
            accountAlias: "备用账号",
            threadID: "thread-abc",
            taskTitleMasked: "quota investigate",
            eventTime: Date(timeIntervalSince1970: 500),
            model: "gpt-5",
            inputTokensDelta: 1_000_000,
            source: .localJSONL
        )
        let differentModel = UsageEvent(
            accountAlias: "主账号",
            threadID: "thread-abc",
            taskTitleMasked: "quota investigate",
            eventTime: Date(timeIntervalSince1970: 500),
            model: "gpt-4.1",
            inputTokensDelta: 1_000_000,
            source: .localJSONL
        )
        let differentSource = UsageEvent(
            accountAlias: "主账号",
            threadID: "thread-xyz",
            taskTitleMasked: "manual import",
            eventTime: Date(timeIntervalSince1970: 900),
            model: "gpt-5",
            inputTokensDelta: 1_000_000,
            source: .manual
        )

        try repository.save(matching)
        try repository.save(differentAccount)
        try repository.save(differentModel)
        try repository.save(differentSource)

        let filtered = try repository.query(
            UsageEventFilter(
                accountAlias: "主账号",
                model: "gpt-5",
                threadQuery: "investigate",
                source: .localJSONL,
                dateFrom: Date(timeIntervalSince1970: 400),
                dateTo: Date(timeIntervalSince1970: 800),
                limit: 50
            )
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.accountAlias, "主账号")
        XCTAssertEqual(filtered.first?.model, "gpt-5")
        XCTAssertEqual(filtered.first?.threadID, "thread-abc")
        XCTAssertEqual(filtered.first?.source, .localJSONL)
    }

    func testSnapshotRepositoryReturnsLatestSnapshot() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteSnapshotRepository(store: store)
        let older = QuotaSnapshot(
            accountAlias: "older",
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHourRemainingPercent: 10,
            weeklyRemainingPercent: 20,
            confidence: .observed
        )
        let newer = QuotaSnapshot(
            accountAlias: "newer",
            capturedAt: Date(timeIntervalSince1970: 200),
            fiveHourRemainingPercent: 55,
            weeklyRemainingPercent: 82,
            confidence: .verified,
            tokenUsage: TokenUsage(inputTokens: 1_000_000),
            estimatedCredits: 12.5
        )

        try repository.save(older)
        try repository.save(newer)
        let latest = try repository.latestSnapshot()

        XCTAssertEqual(latest?.accountAlias, "newer")
        XCTAssertEqual(latest?.fiveHourRemainingPercent, 55)
        XCTAssertEqual(latest?.weeklyRemainingPercent, 82)
        XCTAssertEqual(latest?.confidence, .verified)
        XCTAssertEqual(latest?.tokenUsage.inputTokens, 1_000_000)
        XCTAssertEqual(latest?.estimatedCredits, 12.5)
    }

    func testCollectorOffsetRepositoryPersistsAndUpdatesOffsets() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteCollectorOffsetRepository(store: store)
        let initial = CollectorOffset(
            fileID: "/tmp/rollout.jsonl",
            path: "/tmp/rollout.jsonl",
            lastOffset: 120,
            lastInode: 99,
            lastSeenAt: Date(timeIntervalSince1970: 100)
        )
        let updated = CollectorOffset(
            fileID: "/tmp/rollout.jsonl",
            path: "/tmp/rollout.jsonl",
            lastOffset: 240,
            lastInode: 99,
            lastSeenAt: Date(timeIntervalSince1970: 200)
        )

        try repository.upsert(initial)
        try repository.upsert(updated)

        let loaded = try repository.offset(for: "/tmp/rollout.jsonl")
        XCTAssertEqual(loaded?.lastOffset, 240)
        XCTAssertEqual(loaded?.lastInode, 99)
        XCTAssertEqual(loaded?.lastSeenAt.timeIntervalSince1970, 200)
        XCTAssertEqual(try repository.recent(limit: 10).map(\.fileID), ["/tmp/rollout.jsonl"])
    }

    func testRateCardRepositoryPersistsCards() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteRateCardRepository(store: store)
        let card = RateCard(
            model: "mock-codex",
            version: "fixture",
            sourceURL: URL(string: "https://example.com/rate-card"),
            inputCreditsPerM: 10,
            cachedInputCreditsPerM: 2,
            outputCreditsPerM: 40
        )

        try repository.upsert(card)

        let loaded = try XCTUnwrap(repository.list().first)
        XCTAssertEqual(loaded, card)
        XCTAssertEqual(try repository.manager().estimatedCredits(for: TokenUsage(inputTokens: 1_000_000), model: "mock-codex")?.credits, 10)
    }

    func testAlertEventRepositoryPersistsRecentEventsAndDedupeLookup() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteAlertEventRepository(store: store)
        let suppressed = AlertEvent(
            alertType: .fiveHourRisk,
            accountAlias: "主账号",
            dedupeKey: "主账号|five_hour_risk",
            snapshotCapturedAt: Date(timeIntervalSince1970: 100),
            result: .suppressed,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let delivered = AlertEvent(
            alertType: .fiveHourRisk,
            accountAlias: "主账号",
            dedupeKey: "主账号|five_hour_risk",
            snapshotCapturedAt: Date(timeIntervalSince1970: 200),
            deliveredAt: Date(timeIntervalSince1970: 220),
            result: .delivered,
            message: "sent",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try repository.record(suppressed)
        try repository.record(delivered)

        XCTAssertEqual(try repository.recent(limit: 10).map(\.result), [.delivered, .suppressed])
        XCTAssertEqual(try repository.lastDelivered(dedupeKey: "主账号|five_hour_risk")?.deliveredAt?.timeIntervalSince1970, 220)
        XCTAssertEqual(try repository.lastEvent(dedupeKey: "主账号|five_hour_risk")?.result, .delivered)
        XCTAssertNil(try repository.lastDelivered(dedupeKey: "missing"))
    }

    func testSwitchEventRepositoryPersistsRecentEvents() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let repository = SQLiteSwitchEventRepository(store: store)
        let fromID = UUID()
        let toID = UUID()
        let older = SwitchEvent(
            fromAccountID: fromID,
            fromAccountAlias: "主账号",
            toAccountID: toID,
            toAccountAlias: "备用账号",
            reason: .recommendation,
            providerName: "official_login",
            result: .cancelled,
            message: "cancelled",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = SwitchEvent(
            fromAccountID: fromID,
            fromAccountAlias: "主账号",
            toAccountID: toID,
            toAccountAlias: "备用账号",
            reason: .userRequested,
            providerName: "official_login",
            result: .staleSucceeded,
            message: "stale",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try repository.record(older)
        try repository.record(newer)
        let events = try repository.recent(limit: 10)

        XCTAssertEqual(events.map(\.result), [.staleSucceeded, .cancelled])
        XCTAssertEqual(events.first?.fromAccountID, fromID)
        XCTAssertEqual(events.first?.fromAccountAlias, "主账号")
        XCTAssertEqual(events.first?.toAccountID, toID)
        XCTAssertEqual(events.first?.toAccountAlias, "备用账号")
        XCTAssertEqual(events.first?.reason, .userRequested)
        XCTAssertEqual(events.first?.providerName, "official_login")
        XCTAssertEqual(events.first?.message, "stale")
    }

    func testMaintenanceRepositoryCleansSelectedTables() throws {
        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let usageRepository = SQLiteUsageEventRepository(store: store)
        let snapshotRepository = SQLiteSnapshotRepository(store: store)
        let offsetRepository = SQLiteCollectorOffsetRepository(store: store)
        let auditRepository = SQLiteAuditRepository(store: store)
        let accountRepository = SQLiteAccountRepository(store: store)
        let maintenanceRepository = SQLiteMaintenanceRepository(store: store)

        try usageRepository.save(UsageEvent(eventTime: Date(), inputTokensDelta: 1, source: .manual))
        try snapshotRepository.save(
            QuotaSnapshot(
                accountAlias: "主账号",
                fiveHourRemainingPercent: 50,
                weeklyRemainingPercent: 60,
                confidence: .observed
            )
        )
        try offsetRepository.upsert(
            CollectorOffset(fileID: "file", path: "/tmp/file", lastOffset: 1)
        )
        try auditRepository.record(
            AuditEvent(eventType: .export, objectType: "usage_events", result: .success)
        )
        try accountRepository.upsert(
            Account(alias: "主账号", keychainRef: "cleanup-ref")
        )

        try maintenanceRepository.performCleanup(
            CleanupOptions(
                clearUsageEvents: true,
                clearSnapshots: true,
                clearCollectorOffsets: true,
                clearAlerts: false,
                clearSwitchEvents: false,
                clearAuditEvents: true,
                clearAccounts: true,
                clearKeychainSecrets: false,
                resetSettings: false
            ),
            accountRepository: accountRepository,
            keychainStore: KeychainStore(defaultService: "CodexQuotaManagerTests")
        )

        XCTAssertEqual(try usageRepository.recent(limit: 10).count, 0)
        XCTAssertNil(try snapshotRepository.latestSnapshot())
        XCTAssertEqual(try offsetRepository.recent(limit: 10).count, 0)
        XCTAssertEqual(try auditRepository.recent(limit: 10).count, 0)
        XCTAssertEqual(try accountRepository.listAccounts().count, 0)
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-quota-manager-\(UUID().uuidString)")
            .appendingPathComponent("quota-manager.sqlite")
    }
}
