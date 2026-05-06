import Foundation
import SQLite3

public struct CollectorOffset: Equatable, Sendable {
    public var fileID: String
    public var path: String
    public var lastOffset: UInt64
    public var lastInode: UInt64?
    public var lastSeenAt: Date

    public init(
        fileID: String,
        path: String,
        lastOffset: UInt64,
        lastInode: UInt64? = nil,
        lastSeenAt: Date = Date()
    ) {
        self.fileID = fileID
        self.path = path
        self.lastOffset = lastOffset
        self.lastInode = lastInode
        self.lastSeenAt = lastSeenAt
    }
}

public struct SQLiteCollectorOffsetRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func offset(for fileID: String) throws -> CollectorOffset? {
        try store.withDatabase { db in
            let sql = """
                SELECT file_id, path, last_offset, last_inode, last_seen_at
                FROM collector_offsets
                WHERE file_id = ?
                LIMIT 1
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: fileID)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return readOffset(from: statement)
        }
    }

    public func upsert(_ offset: CollectorOffset) throws {
        try store.withDatabase { db in
            let sql = """
                INSERT INTO collector_offsets(
                    file_id,
                    path,
                    last_offset,
                    last_inode,
                    last_seen_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(file_id) DO UPDATE SET
                    path = excluded.path,
                    last_offset = excluded.last_offset,
                    last_inode = excluded.last_inode,
                    last_seen_at = excluded.last_seen_at,
                    updated_at = excluded.updated_at
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            bindText(statement, index: 1, value: offset.fileID)
            bindText(statement, index: 2, value: offset.path)
            bindInt64(statement, index: 3, value: clampedInt64(offset.lastOffset))
            bindOptionalInt64(statement, index: 4, value: offset.lastInode.map(clampedInt64(_:)))
            bindDouble(statement, index: 5, value: offset.lastSeenAt.timeIntervalSince1970)
            bindDouble(statement, index: 6, value: Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func recent(limit: Int = 200) throws -> [CollectorOffset] {
        try store.withDatabase { db in
            let sql = """
                SELECT file_id, path, last_offset, last_inode, last_seen_at
                FROM collector_offsets
                ORDER BY last_seen_at DESC
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

            var offsets: [CollectorOffset] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                offsets.append(readOffset(from: statement))
            }
            return offsets
        }
    }

    private func readOffset(from statement: OpaquePointer?) -> CollectorOffset {
        CollectorOffset(
            fileID: columnText(statement, index: 0) ?? "",
            path: columnText(statement, index: 1) ?? "",
            lastOffset: UInt64(max(0, sqlite3_column_int64(statement, 2))),
            lastInode: columnOptionalUInt64(statement, index: 3),
            lastSeenAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        )
    }
}

private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func bindDouble(_ statement: OpaquePointer?, index: Int32, value: Double) {
    sqlite3_bind_double(statement, index, value)
}

private func bindInt64(_ statement: OpaquePointer?, index: Int32, value: Int64) {
    sqlite3_bind_int64(statement, index, value)
}

private func bindOptionalInt64(_ statement: OpaquePointer?, index: Int32, value: Int64?) {
    if let value {
        sqlite3_bind_int64(statement, index, value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: text)
}

private func columnOptionalUInt64(_ statement: OpaquePointer?, index: Int32) -> UInt64? {
    if sqlite3_column_type(statement, index) == SQLITE_NULL {
        return nil
    }
    return UInt64(max(0, sqlite3_column_int64(statement, index)))
}

private func clampedInt64(_ value: UInt64) -> Int64 {
    if value > UInt64(Int64.max) {
        return Int64.max
    }
    return Int64(value)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
