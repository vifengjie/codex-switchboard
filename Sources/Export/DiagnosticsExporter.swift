import CodexQuotaCore
import Foundation

public struct DiagnosticsExporter: Sendable {
    public init() {}

    public func export(report: DiagnosticsReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
