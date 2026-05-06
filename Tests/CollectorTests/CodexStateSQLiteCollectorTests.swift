import CodexQuotaCollectors
import Foundation
import SQLite3
import XCTest

final class CodexStateSQLiteCollectorTests: XCTestCase {
    func testStateSQLiteCollectorListsThreadsForCurrentProject() async throws {
        let databaseURL = makeTemporaryDatabaseURL()
        try createStateDatabase(at: databaseURL)
        let collector = CodexStateSQLiteCollector(
            databaseURL: databaseURL,
            cwdFilter: "/workspace/project"
        )

        let threads = try collector.listThreads()
        let result = try await collector.collect()

        XCTAssertEqual(result.threadsDiscovered, 1)
        XCTAssertEqual(threads.map(\.id), ["thread-2"])
        XCTAssertEqual(threads.first?.rolloutPath, "/tmp/thread-2.jsonl")
        XCTAssertEqual(threads.first?.cwd, "/workspace/project")
        XCTAssertEqual(threads.first?.titleMasked, "Codex thread thread-2")
        XCTAssertEqual(threads.first?.tokensUsed, 2_000)
        XCTAssertEqual(threads.first?.model, "gpt-5.2")
        XCTAssertEqual(try collector.rolloutURLs().map(\.path), ["/tmp/thread-2.jsonl"])
    }

    func testStateSQLiteCollectorCanPreserveTitlesWhenRedactionDisabled() throws {
        let databaseURL = makeTemporaryDatabaseURL()
        try createStateDatabase(at: databaseURL)
        let collector = CodexStateSQLiteCollector(
            databaseURL: databaseURL,
            cwdFilter: "/workspace/project",
            redactThreadTitles: false
        )

        let thread = try XCTUnwrap(collector.listThreads().first)

        XCTAssertEqual(thread.titleMasked, "Implement local collector")
    }

    func testStateSQLiteCollectorReturnsEmptyForMissingDatabase() throws {
        let collector = CodexStateSQLiteCollector(databaseURL: makeTemporaryDatabaseURL())

        XCTAssertTrue(try collector.listThreads().isEmpty)
    }

    private func createStateDatabase(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        guard let db else {
            return
        }
        defer {
            sqlite3_close(db)
        }

        try execute(
            db,
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                source TEXT NOT NULL,
                model_provider TEXT NOT NULL,
                cwd TEXT NOT NULL,
                title TEXT NOT NULL,
                sandbox_policy TEXT NOT NULL,
                approval_mode TEXT NOT NULL,
                tokens_used INTEGER NOT NULL DEFAULT 0,
                has_user_event INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL DEFAULT 0,
                archived_at INTEGER,
                git_sha TEXT,
                git_branch TEXT,
                git_origin_url TEXT,
                cli_version TEXT NOT NULL DEFAULT '',
                first_user_message TEXT NOT NULL DEFAULT '',
                agent_nickname TEXT,
                agent_role TEXT,
                memory_mode TEXT NOT NULL DEFAULT 'enabled',
                model TEXT,
                reasoning_effort TEXT,
                agent_path TEXT,
                created_at_ms INTEGER,
                updated_at_ms INTEGER
            );
            INSERT INTO threads(
                id, rollout_path, created_at, updated_at, source, model_provider,
                cwd, title, sandbox_policy, approval_mode, tokens_used, model
            )
            VALUES
                ('thread-1', '/tmp/thread-1.jsonl', 100, 200, 'local', 'openai',
                 '/workspace/other', 'Other project', 'workspace-write', 'on-request', 1000, 'gpt-5.1'),
                ('thread-2', '/tmp/thread-2.jsonl', 300, 400, 'local', 'openai',
                 '/workspace/project', 'Implement local collector', 'workspace-write', 'on-request', 2000, 'gpt-5.2');
            """
        )
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            XCTFail(message)
            return
        }
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-state-tests-\(UUID().uuidString)")
            .appendingPathComponent("state_5.sqlite")
    }
}
