import Foundation

public struct UsageEventFilter: Equatable, Sendable {
    public var accountAlias: String?
    public var model: String?
    public var threadQuery: String?
    public var source: UsageEventSource?
    public var dateFrom: Date?
    public var dateTo: Date?
    public var limit: Int

    public init(
        accountAlias: String? = nil,
        model: String? = nil,
        threadQuery: String? = nil,
        source: UsageEventSource? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        limit: Int = 200
    ) {
        self.accountAlias = accountAlias
        self.model = model
        self.threadQuery = threadQuery
        self.source = source
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.limit = limit
    }

    public static let `default` = UsageEventFilter()
}
