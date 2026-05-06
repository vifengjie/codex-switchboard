import CodexQuotaCollectors
import CodexQuotaStorage
import Foundation
import XCTest

final class LocalJSONLCollectorTests: XCTestCase {
    func testLocalJSONLCollectorReturnsEmptyResultForMissingRoot() async throws {
        let collector = LocalJSONLCollector(rootDirectory: URL(fileURLWithPath: "/tmp/nonexistent-codex-fixture"))
        let result = try await collector.collect()

        XCTAssertEqual(result.usageEventsImported, 0)
        XCTAssertEqual(result.snapshotsImported, 0)
        XCTAssertEqual(result.filesScanned, 0)
    }

    func testLocalJSONLCollectorParsesTokenCountFixture() async throws {
        let collector = LocalJSONLCollector(rootDirectory: try fixtureURL())

        let result = try await collector.collect()

        XCTAssertEqual(result.filesScanned, 1)
        XCTAssertEqual(result.parseFailures, 0)
        XCTAssertEqual(result.usageEventsImported, 1)
        XCTAssertEqual(result.snapshotsImported, 1)

        let event = try XCTUnwrap(result.usageEvents.first)
        XCTAssertEqual(event.accountAlias, "本机 Codex")
        XCTAssertEqual(event.threadID, "token-count-sample")
        XCTAssertEqual(event.inputTokensDelta, 120_000)
        XCTAssertEqual(event.cachedInputTokensDelta, 50_000)
        XCTAssertEqual(event.outputTokensDelta, 11_000)
        XCTAssertEqual(event.reasoningOutputTokensDelta, 4_000)
        XCTAssertEqual(event.source, .localJSONL)

        let snapshot = try XCTUnwrap(result.snapshots.first)
        XCTAssertEqual(snapshot.fiveHourRemainingPercent, 55)
        XCTAssertEqual(snapshot.weeklyRemainingPercent, 82)
        XCTAssertEqual(snapshot.confidence, .observed)
        XCTAssertEqual(snapshot.tokenUsage.inputTokens, 12_400_000)
        XCTAssertEqual(snapshot.tokenUsage.cachedInputTokens, 8_250_000)
        XCTAssertEqual(snapshot.tokenUsage.outputTokens, 1_120_000)
        XCTAssertEqual(snapshot.tokenUsage.reasoningOutputTokens, 430_000)
        XCTAssertEqual(snapshot.capturedAt.timeIntervalSince1970, 1_777_779_007.2, accuracy: 0.001)
    }

    func testLocalJSONLCollectorHandlesMissingUsageFieldsAsPartialSnapshot() async throws {
        let root = try makeTemporaryDirectory()
        let logURL = root.appendingPathComponent("partial.jsonl")
        let line = """
            {"timestamp":"2026-05-03T03:30:07.200Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300}}}}
            """
        try line.write(to: logURL, atomically: true, encoding: .utf8)

        let result = try await LocalJSONLCollector(rootDirectory: root).collect()

        XCTAssertEqual(result.usageEventsImported, 0)
        XCTAssertEqual(result.snapshotsImported, 1)
        XCTAssertEqual(result.snapshots.first?.fiveHourRemainingPercent, 80)
        XCTAssertNil(result.snapshots.first?.weeklyRemainingPercent)
        XCTAssertEqual(result.snapshots.first?.confidence, .partial)
    }

    func testLocalJSONLCollectorUsesOffsetsToAvoidDuplicateImports() async throws {
        let root = try makeTemporaryDirectory()
        let logURL = root.appendingPathComponent("rollout.jsonl")
        try FileManager.default.copyItem(at: try fixtureURL(), to: logURL)

        let store = SQLiteStore(databaseURL: makeTemporaryDatabaseURL())
        try store.migrate()
        let usageRepository = SQLiteUsageEventRepository(store: store)
        let snapshotRepository = SQLiteSnapshotRepository(store: store)
        let offsetRepository = SQLiteCollectorOffsetRepository(store: store)

        let collector = LocalJSONLCollector(
            rootDirectory: root,
            usageEventRepository: usageRepository,
            snapshotRepository: snapshotRepository,
            offsetRepository: offsetRepository
        )

        let first = try await collector.collect()
        let second = try await collector.collect()

        XCTAssertEqual(first.usageEventsImported, 1)
        XCTAssertEqual(first.snapshotsImported, 1)
        XCTAssertEqual(second.usageEventsImported, 0)
        XCTAssertEqual(second.snapshotsImported, 0)
        XCTAssertEqual(try usageRepository.recent(limit: 10).count, 1)
        XCTAssertNotNil(try snapshotRepository.latestSnapshot())
        XCTAssertEqual(try offsetRepository.offset(for: LocalJSONLCollector.fileID(for: logURL))?.lastOffset, UInt64(try Data(contentsOf: logURL).count))
    }

    func testLocalJSONLCollectorCountsInvalidJSONWithoutPersistingRawContent() async throws {
        let root = try makeTemporaryDirectory()
        let logURL = root.appendingPathComponent("invalid.jsonl")
        try "{not-json}\n".write(to: logURL, atomically: true, encoding: .utf8)

        let result = try await LocalJSONLCollector(rootDirectory: root).collect()

        XCTAssertEqual(result.parseFailures, 1)
        XCTAssertTrue(result.usageEvents.isEmpty)
        XCTAssertTrue(result.snapshots.isEmpty)
    }

    private func fixtureURL() throws -> URL {
        if let url = Bundle.module.url(
            forResource: "token-count-sample",
            withExtension: "jsonl",
            subdirectory: "codex-jsonl"
        ) {
            return url
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repositoryRoot
            .appendingPathComponent("Fixtures/codex-jsonl/token-count-sample.jsonl")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-jsonl-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-quota-manager-\(UUID().uuidString)")
            .appendingPathComponent("quota-manager.sqlite")
    }
}
