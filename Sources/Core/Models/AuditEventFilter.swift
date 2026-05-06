import Foundation

public struct AuditEventFilter: Equatable, Sendable {
    public var eventType: AuditEventType?
    public var result: AuditResult?
    public var query: String?
    public var limit: Int

    public init(
        eventType: AuditEventType? = nil,
        result: AuditResult? = nil,
        query: String? = nil,
        limit: Int = 100
    ) {
        self.eventType = eventType
        self.result = result
        self.query = query
        self.limit = limit
    }

    public static let `default` = AuditEventFilter()
}
