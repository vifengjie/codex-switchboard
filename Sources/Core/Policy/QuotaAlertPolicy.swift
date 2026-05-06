import Foundation

public enum QuotaAlertStatus: String, Codable, Sendable {
    case normal
    case warning
    case fiveHourRisk = "five_hour_risk"
    case weeklyCritical = "weekly_critical"
    case executionRisk = "execution_risk"
    case stale
    case failed
    case unavailable
}

public struct QuotaNotificationRequest: Equatable, Sendable {
    public var title: String
    public var body: String
    public var dedupeKey: String
    public var status: QuotaAlertStatus

    public init(title: String, body: String, dedupeKey: String, status: QuotaAlertStatus) {
        self.title = title
        self.body = body
        self.dedupeKey = dedupeKey
        self.status = status
    }
}

public struct QuotaAlertPolicy: Sendable {
    public init() {}

    public func status(for snapshot: QuotaSnapshot, settings: AppSettings, now: Date = Date()) -> QuotaAlertStatus {
        if snapshot.confidence == .failed {
            return .failed
        }
        if snapshot.confidence == .stale || isStale(snapshot, settings: settings, now: now) {
            return .stale
        }

        guard let fiveHour = snapshot.fiveHourRemainingPercent,
              let weekly = snapshot.weeklyRemainingPercent else {
            return .unavailable
        }

        if fiveHour <= 5 || weekly <= 2 {
            return .executionRisk
        }
        if weekly <= settings.weeklyCriticalThresholdPercent {
            return .weeklyCritical
        }
        if fiveHour <= settings.fiveHourRiskThresholdPercent {
            return .fiveHourRisk
        }
        if fiveHour <= 30 || weekly <= 30 {
            return .warning
        }
        return .normal
    }

    public func notificationRequest(
        for snapshot: QuotaSnapshot,
        settings: AppSettings,
        now: Date = Date()
    ) -> QuotaNotificationRequest? {
        let status = status(for: snapshot, settings: settings, now: now)
        let dedupeKey = self.dedupeKey(for: snapshot, status: status)

        switch status {
        case .fiveHourRisk:
            return QuotaNotificationRequest(
                title: "Codex 5H 额度偏低",
                body: "当前账号 \(snapshot.accountAlias) 的 5H 剩余额度为 \(formatPercent(snapshot.fiveHourRemainingPercent))。",
                dedupeKey: dedupeKey,
                status: status
            )
        case .weeklyCritical:
            return QuotaNotificationRequest(
                title: "Codex 1W 额度很低",
                body: "当前账号 \(snapshot.accountAlias) 的 1W 剩余额度为 \(formatPercent(snapshot.weeklyRemainingPercent))。",
                dedupeKey: dedupeKey,
                status: status
            )
        case .executionRisk:
            return QuotaNotificationRequest(
                title: "Codex 执行额度风险",
                body: "当前账号 \(snapshot.accountAlias) 的 5H/1W 剩余额度已接近耗尽。",
                dedupeKey: dedupeKey,
                status: status
            )
        case .failed:
            return QuotaNotificationRequest(
                title: "Codex 额度采集失败",
                body: "最近一次本地采集失败，已保留上一份可用快照。",
                dedupeKey: dedupeKey,
                status: status
            )
        default:
            return nil
        }
    }

    public func dedupeKey(for snapshot: QuotaSnapshot, status: QuotaAlertStatus) -> String {
        "\(snapshot.accountAlias)|\(status.rawValue)"
    }

    public func shouldSuppress(lastDeliveredAt: Date?, settings: AppSettings, now: Date = Date()) -> Bool {
        guard let lastDeliveredAt else {
            return false
        }
        let elapsed = now.timeIntervalSince(lastDeliveredAt)
        return elapsed < TimeInterval(settings.notificationDedupeMinutes * 60)
    }

    private func isStale(_ snapshot: QuotaSnapshot, settings: AppSettings, now: Date) -> Bool {
        now.timeIntervalSince(snapshot.capturedAt) > TimeInterval(settings.snapshotStaleMinutes * 60)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded()))%"
    }
}
