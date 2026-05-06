import CodexQuotaCore
import Foundation
import SQLite3

public struct SQLiteSwitchEventRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func record(_ event: SwitchEvent) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO switch_events(
                    switch_id,
                    from_account_id,
                    from_account_alias,
                    to_account_id,
                    to_account_alias,
                    reason,
                    provider_name,
                    result,
                    message,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: event.id.uuidString)
            bindOptionalText(statement, index: 2, value: event.fromAccountID?.uuidString)
            bindOptionalText(statement, index: 3, value: event.fromAccountAlias)
            bindText(statement, index: 4, value: event.toAccountID.uuidString)
            bindText(statement, index: 5, value: event.toAccountAlias)
            bindText(statement, index: 6, value: event.reason.rawValue)
            bindText(statement, index: 7, value: event.providerName)
            bindText(statement, index: 8, value: event.result.rawValue)
            bindOptionalText(statement, index: 9, value: event.message)
            bindDouble(statement, index: 10, value: event.createdAt.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func recent(limit: Int = 100) throws -> [SwitchEvent] {
        try store.withDatabase { db in
            let sql = """
                SELECT switch_id, from_account_id, from_account_alias,
                       to_account_id, to_account_alias, reason,
                       provider_name, result, message, created_at
                FROM switch_events
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

            bindInt64(statement, index: 1, value: Int64(limit))

            var events: [SwitchEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                events.append(readSwitchEvent(from: statement))
            }
            return events
        }
    }

    private func readSwitchEvent(from statement: OpaquePointer?) -> SwitchEvent {
        let idRaw = columnText(statement, index: 0) ?? UUID().uuidString
        let fromIDRaw = columnText(statement, index: 1)
        let toIDRaw = columnText(statement, index: 3) ?? UUID().uuidString
        let reasonRaw = columnText(statement, index: 5) ?? SwitchReason.userRequested.rawValue
        let resultRaw = columnText(statement, index: 7) ?? SwitchEventResult.failed.rawValue

        return SwitchEvent(
            id: UUID(uuidString: idRaw) ?? UUID(),
            fromAccountID: fromIDRaw.flatMap(UUID.init(uuidString:)),
            fromAccountAlias: columnText(statement, index: 2),
            toAccountID: UUID(uuidString: toIDRaw) ?? UUID(),
            toAccountAlias: columnText(statement, index: 4) ?? "未命名账号",
            reason: SwitchReason(rawValue: reasonRaw) ?? .userRequested,
            providerName: columnText(statement, index: 6) ?? "unknown",
            result: SwitchEventResult(rawValue: resultRaw) ?? .failed,
            message: columnText(statement, index: 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
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

private func bindInt64(_ statement: OpaquePointer?, index: Int32, value: Int64) {
    sqlite3_bind_int64(statement, index, value)
}

private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: text)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
