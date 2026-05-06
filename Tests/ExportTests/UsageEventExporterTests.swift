import CodexQuotaCore
import CodexQuotaExport
import Foundation
import XCTest

final class UsageEventExporterTests: XCTestCase {
    func testCSVExportContainsExpectedColumnsAndRows() throws {
        let exporter = UsageEventExporter()
        let event = UsageEvent(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            accountAlias: "主账号",
            threadID: "thread-1",
            taskTitleMasked: "masked task",
            eventTime: Date(timeIntervalSince1970: 100),
            model: "gpt-5",
            inputTokensDelta: 1_250_000,
            cachedInputTokensDelta: 250_000,
            outputTokensDelta: 500_000,
            reasoningOutputTokensDelta: 125_000,
            estimatedCreditsDelta: 12.5,
            rateCardVersion: "fixture-1",
            source: .localJSONL
        )

        let data = try exporter.export(events: [event], format: .csv)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("event_id,account_alias,thread_id"))
        XCTAssertTrue(text.contains("11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(text.contains("主账号"))
        XCTAssertTrue(text.contains("1.250000"))
        XCTAssertTrue(text.contains("12.5000"))
        XCTAssertFalse(text.contains("auth.json"))
    }

    func testJSONExportUsesStableSchema() throws {
        let exporter = UsageEventExporter()
        let event = UsageEvent(
            accountAlias: "备用账号",
            threadID: "thread-2",
            taskTitleMasked: "task",
            eventTime: Date(timeIntervalSince1970: 200),
            model: "gpt-5-mini",
            inputTokensDelta: 2_000_000,
            cachedInputTokensDelta: 1_000_000,
            outputTokensDelta: 250_000,
            reasoningOutputTokensDelta: 0,
            estimatedCreditsDelta: 8.75,
            rateCardVersion: "fixture-2",
            source: .manual
        )

        let data = try exporter.export(events: [event], format: .json)
        let object = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let row = try XCTUnwrap(object?.first)

        XCTAssertEqual(row["accountAlias"] as? String, "备用账号")
        XCTAssertEqual(row["threadID"] as? String, "thread-2")
        XCTAssertEqual(row["model"] as? String, "gpt-5-mini")
        XCTAssertEqual(row["rateCardVersion"] as? String, "fixture-2")
        XCTAssertEqual(row["source"] as? String, "manual")
        XCTAssertNotNil(row["inputMTokens"])
        XCTAssertNil(row["keychainRef"])
    }

    func testDiagnosticsExportUsesSanitizedSchema() throws {
        let exporter = DiagnosticsExporter()
        let report = DiagnosticsReport(
            appVersion: "dev",
            macOSVersion: "macOS 15",
            collectorVersion: "local-jsonl+state-sqlite",
            settings: .default,
            storageSummary: DiagnosticsStorageSummary(
                accountCount: 2,
                usageEventCount: 10,
                snapshotCount: 3,
                auditEventCount: 4,
                switchEventCount: 1,
                alertEventCount: 2,
                collectorOffsetCount: 1,
                recentOffsets: [
                    DiagnosticsOffsetSummary(
                        path: "/Users/example/.codex/sessions/test.jsonl",
                        lastOffset: 128,
                        lastSeenAt: Date(timeIntervalSince1970: 100)
                    )
                ]
            ),
            sourceSummary: DiagnosticsSourceSummary(
                codexRootPath: "/Users/example/.codex",
                codexRootReadable: true,
                jsonlFileCount: 3,
                stateDatabasePath: "/Users/example/.codex/state_5.sqlite",
                stateDatabaseReadable: true,
                parseFailuresTracked: false
            ),
            latestSnapshot: DiagnosticsSnapshotSummary(
                snapshot: QuotaSnapshot(
                    accountAlias: "主账号",
                    capturedAt: Date(timeIntervalSince1970: 200),
                    fiveHourRemainingPercent: 50,
                    weeklyRemainingPercent: 80,
                    confidence: .observed,
                    estimatedCredits: 12.5
                )
            ),
            lastErrorSummary: nil
        )

        let data = try exporter.export(report: report)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["appVersion"] as? String, "dev")
        XCTAssertNotNil(object?["storageSummary"])
        XCTAssertNotNil(object?["sourceSummary"])
        XCTAssertNil(object?["token"])
        XCTAssertNil(object?["auth"])
        XCTAssertNil(object?["cookie"])
    }
}
