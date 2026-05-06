import CodexQuotaCore
import Foundation

public enum UsageEventExportFormat: String, CaseIterable, Sendable {
    case csv
    case json

    public var fileExtension: String {
        rawValue
    }
}

public struct UsageEventExporter: Sendable {
    public init() {}

    public func export(events: [UsageEvent], format: UsageEventExportFormat) throws -> Data {
        switch format {
        case .csv:
            return Data(csvString(events: events).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(events.map(ExportUsageEvent.init))
        }
    }

    private func csvString(events: [UsageEvent]) -> String {
        let header = [
            "event_id", "account_alias", "thread_id", "task_title_masked",
            "event_time", "model", "input_mtokens", "cached_input_mtokens",
            "output_mtokens", "reasoning_output_mtokens", "estimated_credits",
            "rate_card_version", "source"
        ]
        let rows = events.map { event in
            [
                event.id.uuidString,
                event.accountAlias ?? "",
                event.threadID ?? "",
                event.taskTitleMasked ?? "",
                iso8601String(from: event.eventTime),
                event.model ?? "",
                formatMTokens(event.inputMTokensDelta),
                formatMTokens(event.cachedInputMTokensDelta),
                formatMTokens(event.outputMTokensDelta),
                formatMTokens(event.reasoningOutputMTokensDelta),
                formatCredits(event.estimatedCreditsDelta),
                event.rateCardVersion ?? "",
                event.source.rawValue
            ]
            .map(escapeCSVField(_:))
            .joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }

    private func formatMTokens(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private func formatCredits(_ value: Double?) -> String {
        guard let value else {
            return ""
        }
        return String(format: "%.4f", value)
    }

    private func escapeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private struct ExportUsageEvent: Codable {
        var eventID: UUID
        var accountAlias: String?
        var threadID: String?
        var taskTitleMasked: String?
        var eventTime: Date
        var model: String?
        var inputMTokens: Double
        var cachedInputMTokens: Double
        var outputMTokens: Double
        var reasoningOutputMTokens: Double
        var estimatedCredits: Double?
        var rateCardVersion: String?
        var source: String

        init(event: UsageEvent) {
            self.eventID = event.id
            self.accountAlias = event.accountAlias
            self.threadID = event.threadID
            self.taskTitleMasked = event.taskTitleMasked
            self.eventTime = event.eventTime
            self.model = event.model
            self.inputMTokens = event.inputMTokensDelta
            self.cachedInputMTokens = event.cachedInputMTokensDelta
            self.outputMTokens = event.outputMTokensDelta
            self.reasoningOutputMTokens = event.reasoningOutputMTokensDelta
            self.estimatedCredits = event.estimatedCreditsDelta
            self.rateCardVersion = event.rateCardVersion
            self.source = event.source.rawValue
        }
    }
}
