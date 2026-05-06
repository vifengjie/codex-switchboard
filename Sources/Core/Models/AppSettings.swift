import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var fiveHourRiskThresholdPercent: Double
    public var weeklyCriticalThresholdPercent: Double
    public var notificationDedupeMinutes: Int
    public var snapshotStaleMinutes: Int
    public var redactWorkspaceNames: Bool
    public var redactThreadTitles: Bool

    public init(
        fiveHourRiskThresholdPercent: Double = 15,
        weeklyCriticalThresholdPercent: Double = 5,
        notificationDedupeMinutes: Int = 30,
        snapshotStaleMinutes: Int = 15,
        redactWorkspaceNames: Bool = true,
        redactThreadTitles: Bool = true
    ) {
        self.fiveHourRiskThresholdPercent = fiveHourRiskThresholdPercent
        self.weeklyCriticalThresholdPercent = weeklyCriticalThresholdPercent
        self.notificationDedupeMinutes = notificationDedupeMinutes
        self.snapshotStaleMinutes = snapshotStaleMinutes
        self.redactWorkspaceNames = redactWorkspaceNames
        self.redactThreadTitles = redactThreadTitles
    }

    public static let `default` = AppSettings()
}
