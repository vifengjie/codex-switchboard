import CodexQuotaCore
import Foundation
import SQLite3

public enum SQLiteStoreError: Error, Equatable, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case migrationFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
}

public struct SQLiteStore: Sendable {
    public var databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func migrate() throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try withDatabase { db in
            try execute(
                db,
                """
                PRAGMA journal_mode = WAL;
                PRAGMA foreign_keys = ON;
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS app_settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS accounts (
                    account_id TEXT PRIMARY KEY,
                    alias TEXT NOT NULL,
                    provider TEXT NOT NULL DEFAULT 'unknown',
                    workspace_name TEXT,
                    email_masked TEXT,
                    login_identifier_masked TEXT,
                    plan_type TEXT NOT NULL,
                    seat_type TEXT NOT NULL DEFAULT 'unknown',
                    auth_method TEXT NOT NULL DEFAULT 'unknown',
                    auth_status TEXT NOT NULL,
                    password_required INTEGER NOT NULL DEFAULT 0,
                    verification_methods TEXT NOT NULL DEFAULT '',
                    verification_hint TEXT,
                    keychain_ref TEXT,
                    enabled INTEGER NOT NULL,
                    priority INTEGER NOT NULL,
                    last_switched_at REAL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_accounts_enabled_priority
                    ON accounts(enabled, priority DESC, alias);
                CREATE TABLE IF NOT EXISTS audit_events (
                    audit_id TEXT PRIMARY KEY,
                    event_type TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    object_type TEXT,
                    object_id TEXT,
                    result TEXT NOT NULL,
                    message TEXT,
                    created_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_audit_events_created_at
                    ON audit_events(created_at DESC);
                CREATE TABLE IF NOT EXISTS usage_events (
                    event_id TEXT PRIMARY KEY,
                    account_alias TEXT,
                    thread_id TEXT,
                    task_title_masked TEXT,
                    event_time REAL NOT NULL,
                    model TEXT,
                    input_tokens_delta INTEGER NOT NULL DEFAULT 0,
                    cached_input_tokens_delta INTEGER NOT NULL DEFAULT 0,
                    output_tokens_delta INTEGER NOT NULL DEFAULT 0,
                    reasoning_output_tokens_delta INTEGER NOT NULL DEFAULT 0,
                    estimated_credits_delta REAL,
                    rate_card_version TEXT,
                    source TEXT NOT NULL,
                    created_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_usage_events_event_time
                    ON usage_events(event_time DESC);
                CREATE INDEX IF NOT EXISTS idx_usage_events_account_model
                    ON usage_events(account_alias, model, event_time DESC);
                CREATE TABLE IF NOT EXISTS quota_snapshots (
                    snapshot_id TEXT PRIMARY KEY,
                    account_alias TEXT NOT NULL,
                    captured_at REAL NOT NULL,
                    five_hour_remaining_percent REAL,
                    weekly_remaining_percent REAL,
                    five_hour_resets_at REAL,
                    weekly_resets_at REAL,
                    confidence TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL DEFAULT 0,
                    cached_input_tokens INTEGER NOT NULL DEFAULT 0,
                    output_tokens INTEGER NOT NULL DEFAULT 0,
                    reasoning_output_tokens INTEGER NOT NULL DEFAULT 0,
                    estimated_credits REAL,
                    created_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_quota_snapshots_captured_at
                    ON quota_snapshots(captured_at DESC);
                CREATE TABLE IF NOT EXISTS collector_offsets (
                    file_id TEXT PRIMARY KEY,
                    path TEXT NOT NULL,
                    last_offset INTEGER NOT NULL DEFAULT 0,
                    last_inode INTEGER,
                    last_seen_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_collector_offsets_last_seen
                    ON collector_offsets(last_seen_at DESC);
                CREATE TABLE IF NOT EXISTS rate_cards (
                    model TEXT PRIMARY KEY,
                    version TEXT NOT NULL,
                    source_url TEXT,
                    input_credits_per_m REAL NOT NULL,
                    cached_input_credits_per_m REAL NOT NULL,
                    output_credits_per_m REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS alert_events (
                    alert_id TEXT PRIMARY KEY,
                    alert_type TEXT NOT NULL,
                    account_alias TEXT NOT NULL,
                    dedupe_key TEXT NOT NULL,
                    snapshot_captured_at REAL NOT NULL,
                    delivered_at REAL,
                    result TEXT NOT NULL,
                    message TEXT,
                    created_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_alert_events_dedupe
                    ON alert_events(dedupe_key, delivered_at DESC, created_at DESC);
                CREATE TABLE IF NOT EXISTS switch_events (
                    switch_id TEXT PRIMARY KEY,
                    from_account_id TEXT,
                    from_account_alias TEXT,
                    to_account_id TEXT NOT NULL,
                    to_account_alias TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    provider_name TEXT NOT NULL,
                    result TEXT NOT NULL,
                    message TEXT,
                    created_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_switch_events_created_at
                    ON switch_events(created_at DESC);
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (1, strftime('%s', 'now'));
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (2, strftime('%s', 'now'));
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (3, strftime('%s', 'now'));
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (4, strftime('%s', 'now'));
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (5, strftime('%s', 'now'));
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (6, strftime('%s', 'now'));
                INSERT OR IGNORE INTO schema_migrations(version, applied_at)
                    VALUES (7, strftime('%s', 'now'));
                """
            )
            try ensureAccountColumns(db)
        }
    }

    public func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite open error"
            if let db {
                sqlite3_close(db)
            }
            throw SQLiteStoreError.openFailed(message)
        }

        defer {
            sqlite3_close(db)
        }

        return try body(db)
    }

    public func execute(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.migrationFailed(message)
        }
    }

    private func ensureAccountColumns(_ db: OpaquePointer) throws {
        let existingColumns = try accountColumnNames(db)
        let additions = [
            ("provider", "provider TEXT NOT NULL DEFAULT 'unknown'"),
            ("login_identifier_masked", "login_identifier_masked TEXT"),
            ("seat_type", "seat_type TEXT NOT NULL DEFAULT 'unknown'"),
            ("auth_method", "auth_method TEXT NOT NULL DEFAULT 'unknown'"),
            ("password_required", "password_required INTEGER NOT NULL DEFAULT 0"),
            ("verification_methods", "verification_methods TEXT NOT NULL DEFAULT ''"),
            ("verification_hint", "verification_hint TEXT"),
            ("keychain_ref", "keychain_ref TEXT"),
            ("last_switched_at", "last_switched_at REAL")
        ]

        for addition in additions where !existingColumns.contains(addition.0) {
            try execute(db, "ALTER TABLE accounts ADD COLUMN \(addition.1);")
        }
    }

    private func accountColumnNames(_ db: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(accounts)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer {
            sqlite3_finalize(statement)
        }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 1) else {
                continue
            }
            columns.insert(String(cString: text))
        }
        return columns
    }
}

public struct SQLiteUsageEventRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func save(_ event: UsageEvent) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO usage_events(
                    event_id,
                    account_alias,
                    thread_id,
                    task_title_masked,
                    event_time,
                    model,
                    input_tokens_delta,
                    cached_input_tokens_delta,
                    output_tokens_delta,
                    reasoning_output_tokens_delta,
                    estimated_credits_delta,
                    rate_card_version,
                    source,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(event_id) DO UPDATE SET
                    account_alias = excluded.account_alias,
                    thread_id = excluded.thread_id,
                    task_title_masked = excluded.task_title_masked,
                    event_time = excluded.event_time,
                    model = excluded.model,
                    input_tokens_delta = excluded.input_tokens_delta,
                    cached_input_tokens_delta = excluded.cached_input_tokens_delta,
                    output_tokens_delta = excluded.output_tokens_delta,
                    reasoning_output_tokens_delta = excluded.reasoning_output_tokens_delta,
                    estimated_credits_delta = excluded.estimated_credits_delta,
                    rate_card_version = excluded.rate_card_version,
                    source = excluded.source
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: event.id.uuidString)
            bindOptionalText(statement, index: 2, value: event.accountAlias)
            bindOptionalText(statement, index: 3, value: event.threadID)
            bindOptionalText(statement, index: 4, value: event.taskTitleMasked)
            bindDouble(statement, index: 5, value: event.eventTime.timeIntervalSince1970)
            bindOptionalText(statement, index: 6, value: event.model)
            bindInt64(statement, index: 7, value: Int64(event.inputTokensDelta))
            bindInt64(statement, index: 8, value: Int64(event.cachedInputTokensDelta))
            bindInt64(statement, index: 9, value: Int64(event.outputTokensDelta))
            bindInt64(statement, index: 10, value: Int64(event.reasoningOutputTokensDelta))
            bindOptionalDouble(statement, index: 11, value: event.estimatedCreditsDelta)
            bindOptionalText(statement, index: 12, value: event.rateCardVersion)
            bindText(statement, index: 13, value: event.source.rawValue)
            bindDouble(statement, index: 14, value: Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func recent(limit: Int = 200) throws -> [UsageEvent] {
        try query(.init(limit: limit))
    }

    public func query(_ filter: UsageEventFilter) throws -> [UsageEvent] {
        try store.withDatabase { db in
            var conditions: [String] = []
            if filter.accountAlias?.isEmpty == false {
                conditions.append("account_alias = ?")
            }
            if filter.model?.isEmpty == false {
                conditions.append("model = ?")
            }
            if filter.threadQuery?.isEmpty == false {
                conditions.append("(thread_id LIKE ? OR task_title_masked LIKE ?)")
            }
            if filter.source != nil {
                conditions.append("source = ?")
            }
            if filter.dateFrom != nil {
                conditions.append("event_time >= ?")
            }
            if filter.dateTo != nil {
                conditions.append("event_time <= ?")
            }

            let whereClause = conditions.isEmpty
                ? ""
                : "WHERE " + conditions.joined(separator: " AND ")
            let sql = """
                SELECT event_id, account_alias, thread_id, task_title_masked,
                       event_time, model, input_tokens_delta, cached_input_tokens_delta,
                       output_tokens_delta, reasoning_output_tokens_delta,
                       estimated_credits_delta, rate_card_version, source
                FROM usage_events
                \(whereClause)
                ORDER BY event_time DESC
                LIMIT ?
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            var bindIndex: Int32 = 1
            if let accountAlias = nonEmpty(filter.accountAlias) {
                bindText(statement, index: bindIndex, value: accountAlias)
                bindIndex += 1
            }
            if let model = nonEmpty(filter.model) {
                bindText(statement, index: bindIndex, value: model)
                bindIndex += 1
            }
            if let threadQuery = nonEmpty(filter.threadQuery) {
                let likeValue = "%\(threadQuery)%"
                bindText(statement, index: bindIndex, value: likeValue)
                bindIndex += 1
                bindText(statement, index: bindIndex, value: likeValue)
                bindIndex += 1
            }
            if let source = filter.source {
                bindText(statement, index: bindIndex, value: source.rawValue)
                bindIndex += 1
            }
            if let dateFrom = filter.dateFrom {
                bindDouble(statement, index: bindIndex, value: dateFrom.timeIntervalSince1970)
                bindIndex += 1
            }
            if let dateTo = filter.dateTo {
                bindDouble(statement, index: bindIndex, value: dateTo.timeIntervalSince1970)
                bindIndex += 1
            }
            bindInt64(statement, index: bindIndex, value: Int64(max(1, filter.limit)))

            var events: [UsageEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                events.append(readUsageEvent(from: statement))
            }
            return events
        }
    }

    private func readUsageEvent(from statement: OpaquePointer?) -> UsageEvent {
        let idRaw = columnText(statement, index: 0) ?? UUID().uuidString
        let sourceRaw = columnText(statement, index: 12) ?? UsageEventSource.manual.rawValue

        return UsageEvent(
            id: UUID(uuidString: idRaw) ?? UUID(),
            accountAlias: columnText(statement, index: 1),
            threadID: columnText(statement, index: 2),
            taskTitleMasked: columnText(statement, index: 3),
            eventTime: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            model: columnText(statement, index: 5),
            inputTokensDelta: Int(sqlite3_column_int64(statement, 6)),
            cachedInputTokensDelta: Int(sqlite3_column_int64(statement, 7)),
            outputTokensDelta: Int(sqlite3_column_int64(statement, 8)),
            reasoningOutputTokensDelta: Int(sqlite3_column_int64(statement, 9)),
            estimatedCreditsDelta: columnOptionalDouble(statement, index: 10),
            rateCardVersion: columnText(statement, index: 11),
            source: UsageEventSource(rawValue: sourceRaw) ?? .manual
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct SQLiteAuditRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func record(_ event: AuditEvent) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO audit_events(
                    audit_id,
                    event_type,
                    actor,
                    object_type,
                    object_id,
                    result,
                    message,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: event.id.uuidString)
            bindText(statement, index: 2, value: event.eventType.rawValue)
            bindText(statement, index: 3, value: event.actorName)
            bindOptionalText(statement, index: 4, value: event.objectType)
            bindOptionalText(statement, index: 5, value: event.objectID)
            bindText(statement, index: 6, value: event.result.rawValue)
            bindOptionalText(statement, index: 7, value: event.message)
            bindDouble(statement, index: 8, value: event.createdAt.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func recent(limit: Int = 100) throws -> [AuditEvent] {
        try query(.init(limit: limit))
    }

    public func query(_ filter: AuditEventFilter) throws -> [AuditEvent] {
        try store.withDatabase { db in
            var conditions: [String] = []
            if filter.eventType != nil {
                conditions.append("event_type = ?")
            }
            if filter.result != nil {
                conditions.append("result = ?")
            }
            if filter.query?.isEmpty == false {
                conditions.append("(message LIKE ? OR object_type LIKE ? OR object_id LIKE ?)")
            }
            let whereClause = conditions.isEmpty
                ? ""
                : "WHERE " + conditions.joined(separator: " AND ")
            let sql = """
                SELECT audit_id, event_type, actor, object_type, object_id,
                       result, message, created_at
                FROM audit_events
                \(whereClause)
                ORDER BY created_at DESC
                LIMIT ?
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            var bindIndex: Int32 = 1
            if let eventType = filter.eventType {
                bindText(statement, index: bindIndex, value: eventType.rawValue)
                bindIndex += 1
            }
            if let result = filter.result {
                bindText(statement, index: bindIndex, value: result.rawValue)
                bindIndex += 1
            }
            if let query = nonEmpty(filter.query) {
                let likeValue = "%\(query)%"
                bindText(statement, index: bindIndex, value: likeValue)
                bindIndex += 1
                bindText(statement, index: bindIndex, value: likeValue)
                bindIndex += 1
                bindText(statement, index: bindIndex, value: likeValue)
                bindIndex += 1
            }
            bindInt64(statement, index: bindIndex, value: Int64(max(1, filter.limit)))

            var events: [AuditEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                events.append(readAuditEvent(from: statement))
            }
            return events
        }
    }

    private func readAuditEvent(from statement: OpaquePointer?) -> AuditEvent {
        let idRaw = columnText(statement, index: 0) ?? UUID().uuidString
        let typeRaw = columnText(statement, index: 1) ?? AuditEventType.refresh.rawValue
        let resultRaw = columnText(statement, index: 5) ?? AuditResult.success.rawValue

        return AuditEvent(
            id: UUID(uuidString: idRaw) ?? UUID(),
            eventType: AuditEventType(rawValue: typeRaw) ?? .refresh,
            actorName: columnText(statement, index: 2) ?? NSUserName(),
            objectType: columnText(statement, index: 3),
            objectID: columnText(statement, index: 4),
            result: AuditResult(rawValue: resultRaw) ?? .success,
            message: columnText(statement, index: 6),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct SQLiteAccountRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func listAccounts() throws -> [Account] {
        try store.withDatabase { db in
            let sql = """
                SELECT account_id, alias, provider, workspace_name, email_masked,
                       login_identifier_masked, plan_type, seat_type, auth_method, auth_status,
                       password_required, verification_methods, verification_hint,
                       keychain_ref, enabled, priority, last_switched_at
                FROM accounts
                ORDER BY enabled DESC, priority DESC, alias ASC
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            var accounts: [Account] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                accounts.append(readAccount(from: statement))
            }
            return accounts
        }
    }

    public func account(id: UUID) throws -> Account? {
        try store.withDatabase { db in
            let sql = """
                SELECT account_id, alias, provider, workspace_name, email_masked,
                       login_identifier_masked, plan_type, seat_type, auth_method, auth_status,
                       password_required, verification_methods, verification_hint,
                       keychain_ref, enabled, priority, last_switched_at
                FROM accounts
                WHERE account_id = ?
                LIMIT 1
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: id.uuidString)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return readAccount(from: statement)
        }
    }

    public func upsert(_ account: Account) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO accounts(
                    account_id, alias, provider, workspace_name, email_masked,
                    login_identifier_masked, plan_type, seat_type, auth_method, auth_status,
                    password_required, verification_methods, verification_hint,
                    keychain_ref, enabled, priority, last_switched_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id) DO UPDATE SET
                    alias = excluded.alias,
                    provider = excluded.provider,
                    workspace_name = excluded.workspace_name,
                    email_masked = excluded.email_masked,
                    login_identifier_masked = excluded.login_identifier_masked,
                    plan_type = excluded.plan_type,
                    seat_type = excluded.seat_type,
                    auth_method = excluded.auth_method,
                    auth_status = excluded.auth_status,
                    password_required = excluded.password_required,
                    verification_methods = excluded.verification_methods,
                    verification_hint = excluded.verification_hint,
                    keychain_ref = excluded.keychain_ref,
                    enabled = excluded.enabled,
                    priority = excluded.priority,
                    last_switched_at = excluded.last_switched_at,
                    updated_at = excluded.updated_at
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            let now = Date().timeIntervalSince1970
            bindText(statement, index: 1, value: account.id.uuidString)
            bindText(statement, index: 2, value: account.alias)
            bindText(statement, index: 3, value: account.provider.rawValue)
            bindOptionalText(statement, index: 4, value: account.workspaceName)
            bindOptionalText(statement, index: 5, value: account.emailMasked)
            bindOptionalText(statement, index: 6, value: account.loginIdentifierMasked)
            bindText(statement, index: 7, value: account.planType.rawValue)
            bindText(statement, index: 8, value: account.seatType.rawValue)
            bindText(statement, index: 9, value: account.authMethod.rawValue)
            bindText(statement, index: 10, value: account.authStatus.rawValue)
            bindBool(statement, index: 11, value: account.passwordRequired)
            bindText(statement, index: 12, value: encodeVerificationMethods(account.verificationMethods))
            bindOptionalText(statement, index: 13, value: account.verificationHint)
            bindOptionalText(statement, index: 14, value: account.keychainRef)
            bindBool(statement, index: 15, value: account.enabled)
            bindInt64(statement, index: 16, value: Int64(account.priority))
            bindOptionalDouble(statement, index: 17, value: account.lastSwitchedAt?.timeIntervalSince1970)
            bindDouble(statement, index: 18, value: now)
            bindDouble(statement, index: 19, value: now)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func delete(id: UUID) throws {
        try store.withDatabase { db in
            let sql = "DELETE FROM accounts WHERE account_id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: id.uuidString)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func readAccount(from statement: OpaquePointer?) -> Account {
        let idRaw = columnText(statement, index: 0) ?? UUID().uuidString
        let id = UUID(uuidString: idRaw) ?? UUID()
        let providerRaw = columnText(statement, index: 2) ?? AccountProvider.unknown.rawValue
        let planTypeRaw = columnText(statement, index: 6) ?? PlanType.unknown.rawValue
        let seatTypeRaw = columnText(statement, index: 7) ?? SeatType.unknown.rawValue
        let authMethodRaw = columnText(statement, index: 8) ?? AuthMethod.unknown.rawValue
        let authStatusRaw = columnText(statement, index: 9) ?? AuthStatus.unknown.rawValue

        return Account(
            id: id,
            alias: columnText(statement, index: 1) ?? "未命名账号",
            provider: AccountProvider(rawValue: providerRaw) ?? .unknown,
            workspaceName: columnText(statement, index: 3),
            emailMasked: columnText(statement, index: 4),
            loginIdentifierMasked: columnText(statement, index: 5),
            planType: PlanType(rawValue: planTypeRaw) ?? .unknown,
            seatType: SeatType(rawValue: seatTypeRaw) ?? .unknown,
            authMethod: AuthMethod(rawValue: authMethodRaw) ?? .unknown,
            authStatus: AuthStatus(rawValue: authStatusRaw) ?? .unknown,
            passwordRequired: sqlite3_column_int(statement, 10) == 1,
            verificationMethods: decodeVerificationMethods(columnText(statement, index: 11)),
            verificationHint: columnText(statement, index: 12),
            keychainRef: columnText(statement, index: 13),
            enabled: sqlite3_column_int(statement, 14) == 1,
            priority: Int(sqlite3_column_int64(statement, 15)),
            lastSwitchedAt: columnOptionalDate(statement, index: 16)
        )
    }

    private func encodeVerificationMethods(_ methods: [VerificationMethod]) -> String {
        methods.map(\.rawValue).joined(separator: ",")
    }

    private func decodeVerificationMethods(_ rawValue: String?) -> [VerificationMethod] {
        guard let rawValue, !rawValue.isEmpty else {
            return []
        }
        return rawValue
            .split(separator: ",")
            .compactMap { VerificationMethod(rawValue: String($0)) }
    }
}

public struct SQLiteSettingsRepository: Sendable {
    private let store: SQLiteStore
    private let key = "default"

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func load() throws -> AppSettings? {
        try store.withDatabase { db in
            let sql = "SELECT value FROM app_settings WHERE key = ? LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: key)

            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                return nil
            }

            guard let text = sqlite3_column_text(statement, 0) else {
                return nil
            }

            let data = Data(String(cString: text).utf8)
            do {
                return try JSONDecoder().decode(AppSettings.self, from: data)
            } catch {
                throw SQLiteStoreError.decodingFailed(error.localizedDescription)
            }
        }
    }

    public func save(_ settings: AppSettings) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(settings)
        } catch {
            throw SQLiteStoreError.encodingFailed(error.localizedDescription)
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw SQLiteStoreError.encodingFailed("settings JSON is not valid UTF-8")
        }

        try store.withDatabase { db in
            let sql = """
                INSERT INTO app_settings(key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = excluded.updated_at
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: key)
            bindText(statement, index: 2, value: value)
            bindDouble(statement, index: 3, value: Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func ensureDefaultSettings() throws -> AppSettings {
        if let existing = try load() {
            return existing
        }
        let settings = AppSettings.default
        try save(settings)
        return settings
    }
}

public struct SQLiteSnapshotRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func latestSnapshot() throws -> QuotaSnapshot? {
        try store.withDatabase { db in
            let sql = """
                SELECT account_alias, captured_at, five_hour_remaining_percent,
                       weekly_remaining_percent, five_hour_resets_at, weekly_resets_at,
                       confidence, input_tokens, cached_input_tokens, output_tokens,
                       reasoning_output_tokens, estimated_credits
                FROM quota_snapshots
                ORDER BY captured_at DESC
                LIMIT 1
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            return readLatestSnapshot(from: statement)
        }
    }

    public func latestSnapshot(accountAlias: String) throws -> QuotaSnapshot? {
        try store.withDatabase { db in
            let sql = """
                SELECT account_alias, captured_at, five_hour_remaining_percent,
                       weekly_remaining_percent, five_hour_resets_at, weekly_resets_at,
                       confidence, input_tokens, cached_input_tokens, output_tokens,
                       reasoning_output_tokens, estimated_credits
                FROM quota_snapshots
                WHERE account_alias = ?
                ORDER BY captured_at DESC
                LIMIT 1
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: accountAlias)
            return readLatestSnapshot(from: statement)
        }
    }

    public func save(_ snapshot: QuotaSnapshot) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO quota_snapshots(
                    snapshot_id,
                    account_alias,
                    captured_at,
                    five_hour_remaining_percent,
                    weekly_remaining_percent,
                    five_hour_resets_at,
                    weekly_resets_at,
                    confidence,
                    input_tokens,
                    cached_input_tokens,
                    output_tokens,
                    reasoning_output_tokens,
                    estimated_credits,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: UUID().uuidString)
            bindText(statement, index: 2, value: snapshot.accountAlias)
            bindDouble(statement, index: 3, value: snapshot.capturedAt.timeIntervalSince1970)
            bindOptionalDouble(statement, index: 4, value: snapshot.fiveHourRemainingPercent)
            bindOptionalDouble(statement, index: 5, value: snapshot.weeklyRemainingPercent)
            bindOptionalDouble(statement, index: 6, value: snapshot.fiveHourResetsAt?.timeIntervalSince1970)
            bindOptionalDouble(statement, index: 7, value: snapshot.weeklyResetsAt?.timeIntervalSince1970)
            bindText(statement, index: 8, value: snapshot.confidence.rawValue)
            bindInt64(statement, index: 9, value: Int64(snapshot.tokenUsage.inputTokens))
            bindInt64(statement, index: 10, value: Int64(snapshot.tokenUsage.cachedInputTokens))
            bindInt64(statement, index: 11, value: Int64(snapshot.tokenUsage.outputTokens))
            bindInt64(statement, index: 12, value: Int64(snapshot.tokenUsage.reasoningOutputTokens))
            bindOptionalDouble(statement, index: 13, value: snapshot.estimatedCredits)
            bindDouble(statement, index: 14, value: Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func readLatestSnapshot(from statement: OpaquePointer?) -> QuotaSnapshot? {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            return nil
        }

        let confidenceRaw = columnText(statement, index: 6) ?? SnapshotConfidence.partial.rawValue
        let confidence = SnapshotConfidence(rawValue: confidenceRaw) ?? .partial

        return QuotaSnapshot(
            accountAlias: columnText(statement, index: 0) ?? "未设置",
            capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            fiveHourRemainingPercent: columnOptionalDouble(statement, index: 2),
            weeklyRemainingPercent: columnOptionalDouble(statement, index: 3),
            fiveHourResetsAt: columnOptionalDate(statement, index: 4),
            weeklyResetsAt: columnOptionalDate(statement, index: 5),
            confidence: confidence,
            tokenUsage: TokenUsage(
                inputTokens: Int(sqlite3_column_int64(statement, 7)),
                cachedInputTokens: Int(sqlite3_column_int64(statement, 8)),
                outputTokens: Int(sqlite3_column_int64(statement, 9)),
                reasoningOutputTokens: Int(sqlite3_column_int64(statement, 10))
            ),
            estimatedCredits: columnOptionalDouble(statement, index: 11)
        )
    }
}

private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
    if let value {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func bindDouble(_ statement: OpaquePointer?, index: Int32, value: Double) {
    sqlite3_bind_double(statement, index, value)
}

private func bindOptionalDouble(_ statement: OpaquePointer?, index: Int32, value: Double?) {
    if let value {
        sqlite3_bind_double(statement, index, value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func bindInt64(_ statement: OpaquePointer?, index: Int32, value: Int64) {
    sqlite3_bind_int64(statement, index, value)
}

private func bindBool(_ statement: OpaquePointer?, index: Int32, value: Bool) {
    sqlite3_bind_int(statement, index, value ? 1 : 0)
}

private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: text)
}

private func columnOptionalDouble(_ statement: OpaquePointer?, index: Int32) -> Double? {
    if sqlite3_column_type(statement, index) == SQLITE_NULL {
        return nil
    }
    return sqlite3_column_double(statement, index)
}

private func columnOptionalDate(_ statement: OpaquePointer?, index: Int32) -> Date? {
    columnOptionalDouble(statement, index: index).map { Date(timeIntervalSince1970: $0) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
