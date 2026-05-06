import Foundation

public struct AuditEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var eventType: AuditEventType
    public var actorName: String
    public var objectType: String?
    public var objectID: String?
    public var result: AuditResult
    public var message: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        eventType: AuditEventType,
        actorName: String = NSUserName(),
        objectType: String? = nil,
        objectID: String? = nil,
        result: AuditResult,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventType = eventType
        self.actorName = actorName
        self.objectType = objectType
        self.objectID = objectID
        self.result = result
        self.message = message
        self.createdAt = createdAt
    }
}

public enum AuditEventType: String, Sendable {
    case accountCreate = "account_create"
    case accountUpdate = "account_update"
    case accountDelete = "account_delete"
    case settingsUpdate = "settings_update"
    case refresh = "refresh"
    case switchAccount = "switch_account"
    case export
    case cleanup
}

public enum AuditResult: String, Sendable {
    case success
    case failed
    case cancelled
}
