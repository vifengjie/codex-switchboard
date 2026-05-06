import Foundation

public struct QuotaSnapshot: Equatable, Sendable {
    public var accountAlias: String
    public var capturedAt: Date
    public var fiveHourRemainingPercent: Double?
    public var weeklyRemainingPercent: Double?
    public var fiveHourResetsAt: Date?
    public var weeklyResetsAt: Date?
    public var confidence: SnapshotConfidence
    public var tokenUsage: TokenUsage
    public var estimatedCredits: Double?

    public init(
        accountAlias: String,
        capturedAt: Date = Date(),
        fiveHourRemainingPercent: Double?,
        weeklyRemainingPercent: Double?,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil,
        confidence: SnapshotConfidence,
        tokenUsage: TokenUsage = .zero,
        estimatedCredits: Double? = nil
    ) {
        self.accountAlias = accountAlias
        self.capturedAt = capturedAt
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyResetsAt = weeklyResetsAt
        self.confidence = confidence
        self.tokenUsage = tokenUsage
        self.estimatedCredits = estimatedCredits
    }
}

public enum SnapshotConfidence: String, Sendable {
    case verified
    case observed
    case partial
    case stale
    case failed
}

public extension QuotaSnapshot {
    static let unconfigured = QuotaSnapshot(
        accountAlias: "未设置",
        fiveHourRemainingPercent: nil,
        weeklyRemainingPercent: nil,
        confidence: .partial
    )

    static let storageFailed = QuotaSnapshot(
        accountAlias: "存储异常",
        fiveHourRemainingPercent: nil,
        weeklyRemainingPercent: nil,
        confidence: .failed
    )

    static let mockHealthy = QuotaSnapshot(
        accountAlias: "主账号 / Mock",
        fiveHourRemainingPercent: 55,
        weeklyRemainingPercent: 82,
        confidence: .observed,
        tokenUsage: TokenUsage(
            inputTokens: 12_400_000,
            cachedInputTokens: 8_250_000,
            outputTokens: 1_120_000,
            reasoningOutputTokens: 430_000
        ),
        estimatedCredits: 1_881.25
    )

    static let mockRefreshing = QuotaSnapshot(
        accountAlias: "主账号 / Mock",
        fiveHourRemainingPercent: nil,
        weeklyRemainingPercent: nil,
        confidence: .stale
    )
}
