import Foundation

public struct QuotaStatusPresenter: Sendable {
    public init() {}

    public func menuBarTitle(for snapshot: QuotaSnapshot) -> String {
        if snapshot.accountAlias == "未设置", snapshot.fiveHourRemainingPercent == nil, snapshot.weeklyRemainingPercent == nil {
            return "Cdx 未设置"
        }

        if snapshot.confidence == .stale,
           snapshot.fiveHourRemainingPercent == nil,
           snapshot.accountAlias == QuotaSnapshot.mockRefreshing.accountAlias {
            return "Cdx 刷新中..."
        }

        let fiveHour = formatPercent(snapshot.fiveHourRemainingPercent)
        let weekly = formatPercent(snapshot.weeklyRemainingPercent)
        let suffix = snapshot.confidence == .stale || snapshot.confidence == .failed ? " !" : ""
        return "Cdx 5H \(fiveHour) 1W \(weekly)\(suffix)"
    }

    public func detailLine(for snapshot: QuotaSnapshot) -> String {
        let fiveHour = formatPercent(snapshot.fiveHourRemainingPercent)
        let weekly = formatPercent(snapshot.weeklyRemainingPercent)
        return "5 小时额度 \(fiveHour)，1 周额度 \(weekly)"
    }

    public func tooltip(for snapshot: QuotaSnapshot) -> String {
        let capturedAt = Self.tooltipDateFormatter.string(from: snapshot.capturedAt)
        return """
        Codex Quota Manager
        账号：\(snapshot.accountAlias)
        5H 剩余：\(formatPercent(snapshot.fiveHourRemainingPercent))
        1W 剩余：\(formatPercent(snapshot.weeklyRemainingPercent))
        快照：\(capturedAt)
        """
    }

    public func formatMTokens(_ value: Double) -> String {
        if value > 0, value < 0.001 {
            return "<0.001M"
        }
        if value < 10 {
            return String(format: "%.3fM", value)
        }
        if value < 100 {
            return String(format: "%.2fM", value)
        }
        return String(format: "%.1fM", value)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded()))%"
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
