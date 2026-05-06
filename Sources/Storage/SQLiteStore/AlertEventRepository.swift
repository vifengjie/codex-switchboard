import CodexQuotaCore
import Foundation
import SQLite3

public struct SQLiteAlertEventRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func record(_ event: AlertEvent) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO alert_events(
                    alert_id,
                    alert_type,
                    account_alias,
                    dedupe_key,
                    snapshot_captured_at,
                    delivered_at,
                    result,
                    message,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: event.id.uuidString)
            bindText(statement, index: 2, value: event.alertType.rawValue)
            bindText(statement, index: 3, value: event.accountAlias)
            bindText(statement, index: 4, value: event.dedupeKey)
            bindDouble(statement, index: 5, value: event.snapshotCapturedAt.timeIntervalSince1970)
            bindOptionalDouble(statement, index: 6, value: event.deliveredAt?.timeIntervalSince1970)
            bindText(statement, index: 7, value: event.result.rawValue)
            bindOptionalText(statement, index: 8, value: event.message)
            bindDouble(statement, index: 9, value: event.createdAt.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func lastDelivered(dedupeKey: String) throws -> AlertEvent? {
        try lastEvent(dedupeKey: dedupeKey, result: .delivered)
    }

    public func lastEvent(dedupeKey: String, result: AlertDeliveryResult? = nil) throws -> AlertEvent? {
        try store.withDatabase { db in
            let sql: String
            if result == nil {
                sql = """
                    SELECT alert_id, alert_type, account_alias, dedupe_key,
                           snapshot_captured_at, delivered_at, result, message, created_at
                    FROM alert_events
                    WHERE dedupe_key = ?
                    ORDER BY created_at DESC
                    LIMIT 1
                    """
            } else {
                sql = """
                    SELECT alert_id, alert_type, account_alias, dedupe_key,
                           snapshot_captured_at, delivered_at, result, message, created_at
                    FROM alert_events
                    WHERE dedupe_key = ? AND result = ?
                    ORDER BY delivered_at DESC, created_at DESC
                    LIMIT 1
                    """
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: dedupeKey)
            if let result {
                bindText(statement, index: 2, value: result.rawValue)
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return readAlertEvent(from: statement)
        }
    }

    public func recent(limit: Int = 100) throws -> [AlertEvent] {
        try store.withDatabase { db in
            let sql = """
                SELECT alert_id, alert_type, account_alias, dedupe_key,
                       snapshot_captured_at, delivered_at, result, message, created_at
                FROM alert_events
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

            var events: [AlertEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                events.append(readAlertEvent(from: statement))
            }
            return events
        }
    }

    private func readAlertEvent(from statement: OpaquePointer?) -> AlertEvent {
        let idRaw = columnText(statement, index: 0) ?? UUID().uuidString
        let typeRaw = columnText(statement, index: 1) ?? QuotaAlertStatus.unavailable.rawValue
        let resultRaw = columnText(statement, index: 6) ?? AlertDeliveryResult.failed.rawValue

        return AlertEvent(
            id: UUID(uuidString: idRaw) ?? UUID(),
            alertType: QuotaAlertStatus(rawValue: typeRaw) ?? .unavailable,
            accountAlias: columnText(statement, index: 2) ?? "",
            dedupeKey: columnText(statement, index: 3) ?? "",
            snapshotCapturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            deliveredAt: columnOptionalDate(statement, index: 5),
            result: AlertDeliveryResult(rawValue: resultRaw) ?? .failed,
            message: columnText(statement, index: 7),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
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
