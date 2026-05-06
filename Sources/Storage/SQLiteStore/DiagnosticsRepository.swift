import CodexQuotaCore
import Foundation
import SQLite3

public struct SQLiteDiagnosticsRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func storageSummary() throws -> DiagnosticsStorageSummary {
        try store.withDatabase { db in
            DiagnosticsStorageSummary(
                accountCount: try count(table: "accounts", db: db),
                usageEventCount: try count(table: "usage_events", db: db),
                snapshotCount: try count(table: "quota_snapshots", db: db),
                auditEventCount: try count(table: "audit_events", db: db),
                switchEventCount: try count(table: "switch_events", db: db),
                alertEventCount: try count(table: "alert_events", db: db),
                collectorOffsetCount: try count(table: "collector_offsets", db: db),
                recentOffsets: try recentOffsets()
            )
        }
    }

    private func count(table: String, db: OpaquePointer) throws -> Int {
        let sql = "SELECT COUNT(*) FROM \(table)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func recentOffsets(limit: Int = 20) throws -> [DiagnosticsOffsetSummary] {
        let offsets = try SQLiteCollectorOffsetRepository(store: store).recent(limit: limit)
        return offsets.map {
            DiagnosticsOffsetSummary(
                path: $0.path,
                lastOffset: $0.lastOffset,
                lastSeenAt: $0.lastSeenAt
            )
        }
    }
}
