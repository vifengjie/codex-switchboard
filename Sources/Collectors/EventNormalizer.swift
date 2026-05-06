import CodexQuotaCore
import Foundation

public enum CodexJSONLParseError: Error, Equatable, Sendable {
    case invalidJSONObject
}

public struct NormalizedCollectorEvent: Equatable, Sendable {
    public var usageEvent: UsageEvent?
    public var snapshot: QuotaSnapshot?

    public init(usageEvent: UsageEvent? = nil, snapshot: QuotaSnapshot? = nil) {
        self.usageEvent = usageEvent
        self.snapshot = snapshot
    }
}

public struct CodexEventNormalizer: Sendable {
    public var accountAlias: String
    private let quotaEngine: QuotaEngine

    public init(accountAlias: String = "本机 Codex", quotaEngine: QuotaEngine = QuotaEngine()) {
        self.accountAlias = accountAlias
        self.quotaEngine = quotaEngine
    }

    public func normalizeJSONLine(
        _ data: Data,
        sourceURL: URL,
        lineOffset: UInt64
    ) throws -> NormalizedCollectorEvent? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CodexJSONLParseError.invalidJSONObject
        }

        let payload = dictionary(root["payload"])
        guard isTokenCountEvent(root: root, payload: payload) else {
            return nil
        }

        let info = dictionary(payload?["info"]) ?? dictionary(root["info"])
        let lastUsage = tokenUsage(from: dictionary(info?["last_token_usage"])
            ?? dictionary(payload?["last_token_usage"])
            ?? dictionary(root["last_token_usage"]))
        let totalUsage = tokenUsage(from: dictionary(info?["total_token_usage"])
            ?? dictionary(payload?["total_token_usage"])
            ?? dictionary(root["total_token_usage"]))
        let rateLimits = dictionary(payload?["rate_limits"])
            ?? dictionary(info?["rate_limits"])
            ?? dictionary(root["rate_limits"])
        let windows = quotaWindows(from: rateLimits)

        let eventTime = firstDate(
            root["timestamp"],
            root["time"],
            root["created_at"],
            payload?["timestamp"],
            payload?["time"],
            payload?["created_at"]
        ) ?? Date()
        let model = firstString(
            root["model"],
            payload?["model"],
            info?["model"]
        )
        let threadID = firstString(
            root["thread_id"],
            root["conversation_id"],
            payload?["thread_id"],
            payload?["conversation_id"]
        ) ?? sourceURL.deletingPathExtension().lastPathComponent

        var usageEvent: UsageEvent?
        if let lastUsage, lastUsage.hasAnyTokenField {
            usageEvent = UsageEvent(
                id: stableEventID(sourceURL: sourceURL, lineOffset: lineOffset, lineData: data),
                accountAlias: accountAlias,
                threadID: threadID,
                taskTitleMasked: nil,
                eventTime: eventTime,
                model: model,
                inputTokensDelta: lastUsage.usage.inputTokens,
                cachedInputTokensDelta: lastUsage.usage.cachedInputTokens,
                outputTokensDelta: lastUsage.usage.outputTokens,
                reasoningOutputTokensDelta: lastUsage.usage.reasoningOutputTokens,
                estimatedCreditsDelta: nil,
                rateCardVersion: nil,
                source: .localJSONL
            )
        }

        var snapshot: QuotaSnapshot?
        if totalUsage != nil || windows.hasAnyQuotaField {
            snapshot = QuotaSnapshot(
                accountAlias: accountAlias,
                capturedAt: eventTime,
                fiveHourRemainingPercent: quotaEngine.remainingPercent(fromUsedPercent: windows.fiveHourUsedPercent),
                weeklyRemainingPercent: quotaEngine.remainingPercent(fromUsedPercent: windows.weeklyUsedPercent),
                fiveHourResetsAt: windows.fiveHourResetsAt,
                weeklyResetsAt: windows.weeklyResetsAt,
                confidence: snapshotConfidence(totalUsage: totalUsage, windows: windows),
                tokenUsage: totalUsage?.usage ?? lastUsage?.usage ?? .zero,
                estimatedCredits: nil
            )
        }

        if usageEvent == nil, snapshot == nil {
            return nil
        }
        return NormalizedCollectorEvent(usageEvent: usageEvent, snapshot: snapshot)
    }

    private func isTokenCountEvent(root: [String: Any], payload: [String: Any]?) -> Bool {
        let rootType = firstString(root["type"], root["event_type"])
        let payloadType = firstString(payload?["type"], payload?["event_type"])
        return rootType == "token_count" || payloadType == "token_count"
    }

    private func snapshotConfidence(
        totalUsage: TokenUsageObservation?,
        windows: QuotaWindowObservation
    ) -> SnapshotConfidence {
        if totalUsage != nil, windows.fiveHourUsedPercent != nil, windows.weeklyUsedPercent != nil {
            return .observed
        }
        return .partial
    }
}

private struct TokenUsageObservation {
    var usage: TokenUsage
    var hasAnyTokenField: Bool
}

private struct RateLimitWindow {
    var usedPercent: Double?
    var windowMinutes: Int?
    var resetsAt: Date?

    var hasAnyQuotaField: Bool {
        usedPercent != nil || resetsAt != nil || windowMinutes != nil
    }
}

private struct QuotaWindowObservation {
    var fiveHourUsedPercent: Double?
    var weeklyUsedPercent: Double?
    var fiveHourResetsAt: Date?
    var weeklyResetsAt: Date?

    var hasAnyQuotaField: Bool {
        fiveHourUsedPercent != nil
            || weeklyUsedPercent != nil
            || fiveHourResetsAt != nil
            || weeklyResetsAt != nil
    }
}

private func dictionary(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func firstString(_ values: Any?...) -> String? {
    for value in values {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
    }
    return nil
}

private func firstDate(_ values: Any?...) -> Date? {
    for value in values {
        if let date = parsedDate(value) {
            return date
        }
    }
    return nil
}

private func parsedDate(_ value: Any?) -> Date? {
    if let number = value as? NSNumber {
        return epochDate(number.doubleValue)
    }
    guard let string = value as? String, !string.isEmpty else {
        return nil
    }
    if let seconds = Double(string) {
        return epochDate(seconds)
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

private func epochDate(_ raw: Double) -> Date {
    if raw > 1_000_000_000_000 {
        return Date(timeIntervalSince1970: raw / 1_000)
    }
    return Date(timeIntervalSince1970: raw)
}

private func tokenUsage(from dictionary: [String: Any]?) -> TokenUsageObservation? {
    guard let dictionary else {
        return nil
    }

    let input = intValue(dictionary["input_tokens"])
    let cached = intValue(dictionary["cached_input_tokens"])
    let output = intValue(dictionary["output_tokens"])
    let reasoning = intValue(dictionary["reasoning_output_tokens"])
    let hasAny = input != nil || cached != nil || output != nil || reasoning != nil

    guard hasAny else {
        return nil
    }

    return TokenUsageObservation(
        usage: TokenUsage(
            inputTokens: input ?? 0,
            cachedInputTokens: cached ?? 0,
            outputTokens: output ?? 0,
            reasoningOutputTokens: reasoning ?? 0
        ),
        hasAnyTokenField: hasAny
    )
}

private func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let string = value as? String {
        return Int(string)
    }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let string = value as? String {
        return Double(string)
    }
    return nil
}

private func quotaWindows(from dictionary: [String: Any]?) -> QuotaWindowObservation {
    guard let dictionary else {
        return QuotaWindowObservation()
    }

    let primary = rateLimitWindow(from: dictionary["primary"])
    let secondary = rateLimitWindow(from: dictionary["secondary"])
    let fiveHourNamed = rateLimitWindow(from: dictionary["five_hour"])
    let weeklyNamed = rateLimitWindow(from: dictionary["weekly"])

    let fiveHour = firstMatchingWindow(
        preferred: fiveHourNamed,
        primary,
        secondary,
        expectedMinutes: 300,
        fallback: primary
    )
    let weekly = firstMatchingWindow(
        preferred: weeklyNamed,
        secondary,
        primary,
        expectedMinutes: 10_080,
        fallback: secondary
    )

    return QuotaWindowObservation(
        fiveHourUsedPercent: fiveHour?.usedPercent,
        weeklyUsedPercent: weekly?.usedPercent,
        fiveHourResetsAt: fiveHour?.resetsAt,
        weeklyResetsAt: weekly?.resetsAt
    )
}

private func rateLimitWindow(from value: Any?) -> RateLimitWindow? {
    guard let dictionary = dictionary(value) else {
        return nil
    }
    return RateLimitWindow(
        usedPercent: doubleValue(dictionary["used_percent"]),
        windowMinutes: intValue(dictionary["window_minutes"]),
        resetsAt: parsedDate(dictionary["resets_at"])
    )
}

private func firstMatchingWindow(
    preferred: RateLimitWindow?,
    _ candidates: RateLimitWindow?...,
    expectedMinutes: Int,
    fallback: RateLimitWindow?
) -> RateLimitWindow? {
    if let preferred, preferred.hasAnyQuotaField {
        return preferred
    }
    for candidate in candidates {
        if candidate?.windowMinutes == expectedMinutes {
            return candidate
        }
    }
    if let fallback, fallback.windowMinutes == nil, fallback.hasAnyQuotaField {
        return fallback
    }
    return nil
}

private func stableEventID(sourceURL: URL, lineOffset: UInt64, lineData: Data) -> UUID {
    var hashA: UInt64 = 14_695_981_039_346_656_037
    var hashB: UInt64 = 10_995_116_282_111
    let seed = "\(sourceURL.standardizedFileURL.path):\(lineOffset)"

    func feed(_ byte: UInt8, into hash: inout UInt64) {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }

    for byte in seed.utf8 {
        feed(byte, into: &hashA)
        feed(byte &+ 31, into: &hashB)
    }
    for byte in lineData {
        feed(byte, into: &hashA)
        feed(byte &+ 17, into: &hashB)
    }

    var bytes = bigEndianBytes(hashA) + bigEndianBytes(hashB)
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private func bigEndianBytes(_ value: UInt64) -> [UInt8] {
    [
        UInt8((value >> 56) & 0xff),
        UInt8((value >> 48) & 0xff),
        UInt8((value >> 40) & 0xff),
        UInt8((value >> 32) & 0xff),
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]
}
