import Foundation

public struct AlertEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var alertType: QuotaAlertStatus
    public var accountAlias: String
    public var dedupeKey: String
    public var snapshotCapturedAt: Date
    public var deliveredAt: Date?
    public var result: AlertDeliveryResult
    public var message: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        alertType: QuotaAlertStatus,
        accountAlias: String,
        dedupeKey: String,
        snapshotCapturedAt: Date,
        deliveredAt: Date? = nil,
        result: AlertDeliveryResult,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.alertType = alertType
        self.accountAlias = accountAlias
        self.dedupeKey = dedupeKey
        self.snapshotCapturedAt = snapshotCapturedAt
        self.deliveredAt = deliveredAt
        self.result = result
        self.message = message
        self.createdAt = createdAt
    }
}

public enum AlertDeliveryResult: String, Sendable {
    case pending
    case delivered
    case suppressed
    case failed
}
