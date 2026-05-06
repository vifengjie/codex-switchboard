import CodexQuotaCore
import Foundation
import SQLite3

public enum CodexStateSQLiteCollectorError: Error, Equatable, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

public struct CodexThreadMetadata: Equatable, Identifiable, Sendable {
    public var id: String
    public var rolloutPath: String
    public var cwd: String
    public var titleMasked: String?
    public var tokensUsed: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var model: String?

    public init(
        id: String,
        rolloutPath: String,
        cwd: String,
        titleMasked: String? = nil,
        tokensUsed: Int,
        createdAt: Date,
        updatedAt: Date,
        model: String? = nil
    ) {
        self.id = id
        self.rolloutPath = rolloutPath
        self.cwd = cwd
        self.titleMasked = titleMasked
        self.tokensUsed = tokensUsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
    }
}

public struct CodexStateSQLiteCollector: CollectorAdapter {
    public let sourceName = "state_sqlite"
    public var databaseURL: URL
    public var cwdFilter: String?
    public var redactThreadTitles: Bool

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/state_5.sqlite"),
        cwdFilter: String? = nil,
        redactThreadTitles: Bool = true
    ) {
        self.databaseURL = databaseURL
        self.cwdFilter = cwdFilter
        self.redactThreadTitles = redactThreadTitles
    }

    public func collect() async throws -> CollectorResult {
        let threads = try listThreads(cwd: cwdFilter)
        return CollectorResult(
            usageEventsImported: 0,
            snapshotsImported: 0,
            threadsDiscovered: threads.count
        )
    }

    public func listThreads(cwd: String? = nil) throws -> [CodexThreadMetadata] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        return try withReadOnlyDatabase { db in
            guard try tableExists("threads", db: db) else {
                return []
            }

            let selectedCWD = cwd ?? cwdFilter
            let sql: String
            if selectedCWD == nil {
                sql = """
                    SELECT id, rollout_path, cwd, title, tokens_used,
                           created_at, updated_at, model
                    FROM threads
                    ORDER BY updated_at DESC
                    """
            } else {
                sql = """
                    SELECT id, rollout_path, cwd, title, tokens_used,
                           created_at, updated_at, model
                    FROM threads
                    WHERE cwd = ?
                    ORDER BY updated_at DESC
                    """
            }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw CodexStateSQLiteCollectorError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer {
                sqlite3_finalize(statement)
            }

            if let selectedCWD {
                bindText(statement, index: 1, value: selectedCWD)
            }

            var threads: [CodexThreadMetadata] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    break
                }
                guard result == SQLITE_ROW else {
                    throw CodexStateSQLiteCollectorError.stepFailed(String(cString: sqlite3_errmsg(db)))
                }
                threads.append(readThread(from: statement))
            }
            return threads
        }
    }

    public func rolloutURLs(cwd: String? = nil) throws -> [URL] {
        try listThreads(cwd: cwd)
            .map(\.rolloutPath)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    private func withReadOnlyDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite open error"
            if let db {
                sqlite3_close(db)
            }
            throw CodexStateSQLiteCollectorError.openFailed(message)
        }
        defer {
            sqlite3_close(db)
        }
        return try body(db)
    }

    private func tableExists(_ tableName: String, db: OpaquePointer) throws -> Bool {
        let sql = """
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = ?
            LIMIT 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CodexStateSQLiteCollectorError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer {
            sqlite3_finalize(statement)
        }

        bindText(statement, index: 1, value: tableName)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func readThread(from statement: OpaquePointer?) -> CodexThreadMetadata {
        let id = columnText(statement, index: 0) ?? ""
        let rawTitle = columnText(statement, index: 3)
        return CodexThreadMetadata(
            id: id,
            rolloutPath: columnText(statement, index: 1) ?? "",
            cwd: columnText(statement, index: 2) ?? "",
            titleMasked: maskedTitle(rawTitle, threadID: id),
            tokensUsed: Int(sqlite3_column_int64(statement, 4)),
            createdAt: timestampDate(sqlite3_column_int64(statement, 5)),
            updatedAt: timestampDate(sqlite3_column_int64(statement, 6)),
            model: columnText(statement, index: 7)
        )
    }

    private func maskedTitle(_ title: String?, threadID: String) -> String? {
        guard let title, !title.isEmpty else {
            return nil
        }
        if !redactThreadTitles {
            return title
        }
        let prefix = String(threadID.prefix(8))
        return prefix.isEmpty ? "Codex thread" : "Codex thread \(prefix)"
    }
}

private func timestampDate(_ raw: Int64) -> Date {
    if raw > 1_000_000_000_000 {
        return Date(timeIntervalSince1970: Double(raw) / 1_000)
    }
    return Date(timeIntervalSince1970: Double(raw))
}

private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: text)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
