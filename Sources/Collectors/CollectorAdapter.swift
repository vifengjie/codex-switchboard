import CodexQuotaCore
import Foundation

public protocol CollectorAdapter: Sendable {
    var sourceName: String { get }

    func collect() async throws -> CollectorResult
}

public struct CollectorResult: Equatable, Sendable {
    public var usageEventsImported: Int
    public var snapshotsImported: Int
    public var filesScanned: Int
    public var threadsDiscovered: Int
    public var parseFailures: Int
    public var usageEvents: [UsageEvent]
    public var snapshots: [QuotaSnapshot]

    public init(
        usageEventsImported: Int,
        snapshotsImported: Int,
        filesScanned: Int = 0,
        threadsDiscovered: Int = 0,
        parseFailures: Int = 0,
        usageEvents: [UsageEvent] = [],
        snapshots: [QuotaSnapshot] = []
    ) {
        self.usageEventsImported = usageEventsImported
        self.snapshotsImported = snapshotsImported
        self.filesScanned = filesScanned
        self.threadsDiscovered = threadsDiscovered
        self.parseFailures = parseFailures
        self.usageEvents = usageEvents
        self.snapshots = snapshots
    }
}
