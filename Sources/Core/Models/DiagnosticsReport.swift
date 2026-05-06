import Foundation

public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var appVersion: String
    public var macOSVersion: String
    public var collectorVersion: String
    public var settings: AppSettings
    public var storageSummary: DiagnosticsStorageSummary
    public var sourceSummary: DiagnosticsSourceSummary
    public var latestSnapshot: DiagnosticsSnapshotSummary?
    public var lastErrorSummary: String?

    public init(
        generatedAt: Date = Date(),
        appVersion: String,
        macOSVersion: String,
        collectorVersion: String,
        settings: AppSettings,
        storageSummary: DiagnosticsStorageSummary,
        sourceSummary: DiagnosticsSourceSummary,
        latestSnapshot: DiagnosticsSnapshotSummary?,
        lastErrorSummary: String?
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.collectorVersion = collectorVersion
        self.settings = settings
        self.storageSummary = storageSummary
        self.sourceSummary = sourceSummary
        self.latestSnapshot = latestSnapshot
        self.lastErrorSummary = lastErrorSummary
    }
}

public struct DiagnosticsStorageSummary: Codable, Equatable, Sendable {
    public var accountCount: Int
    public var usageEventCount: Int
    public var snapshotCount: Int
    public var auditEventCount: Int
    public var switchEventCount: Int
    public var alertEventCount: Int
    public var collectorOffsetCount: Int
    public var recentOffsets: [DiagnosticsOffsetSummary]

    public init(
        accountCount: Int,
        usageEventCount: Int,
        snapshotCount: Int,
        auditEventCount: Int,
        switchEventCount: Int,
        alertEventCount: Int,
        collectorOffsetCount: Int,
        recentOffsets: [DiagnosticsOffsetSummary]
    ) {
        self.accountCount = accountCount
        self.usageEventCount = usageEventCount
        self.snapshotCount = snapshotCount
        self.auditEventCount = auditEventCount
        self.switchEventCount = switchEventCount
        self.alertEventCount = alertEventCount
        self.collectorOffsetCount = collectorOffsetCount
        self.recentOffsets = recentOffsets
    }
}

public struct DiagnosticsOffsetSummary: Codable, Equatable, Sendable {
    public var path: String
    public var lastOffset: UInt64
    public var lastSeenAt: Date

    public init(path: String, lastOffset: UInt64, lastSeenAt: Date) {
        self.path = path
        self.lastOffset = lastOffset
        self.lastSeenAt = lastSeenAt
    }
}

public struct DiagnosticsSourceSummary: Codable, Equatable, Sendable {
    public var codexRootPath: String
    public var codexRootReadable: Bool
    public var jsonlFileCount: Int
    public var stateDatabasePath: String
    public var stateDatabaseReadable: Bool
    public var parseFailuresTracked: Bool

    public init(
        codexRootPath: String,
        codexRootReadable: Bool,
        jsonlFileCount: Int,
        stateDatabasePath: String,
        stateDatabaseReadable: Bool,
        parseFailuresTracked: Bool
    ) {
        self.codexRootPath = codexRootPath
        self.codexRootReadable = codexRootReadable
        self.jsonlFileCount = jsonlFileCount
        self.stateDatabasePath = stateDatabasePath
        self.stateDatabaseReadable = stateDatabaseReadable
        self.parseFailuresTracked = parseFailuresTracked
    }
}

public struct DiagnosticsSnapshotSummary: Codable, Equatable, Sendable {
    public var accountAlias: String
    public var capturedAt: Date
    public var fiveHourRemainingPercent: Double?
    public var weeklyRemainingPercent: Double?
    public var confidence: String
    public var estimatedCredits: Double?

    public init(snapshot: QuotaSnapshot) {
        self.accountAlias = snapshot.accountAlias
        self.capturedAt = snapshot.capturedAt
        self.fiveHourRemainingPercent = snapshot.fiveHourRemainingPercent
        self.weeklyRemainingPercent = snapshot.weeklyRemainingPercent
        self.confidence = snapshot.confidence.rawValue
        self.estimatedCredits = snapshot.estimatedCredits
    }
}
