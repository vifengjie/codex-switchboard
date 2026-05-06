import Foundation

public struct UsageEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var accountAlias: String?
    public var threadID: String?
    public var taskTitleMasked: String?
    public var eventTime: Date
    public var model: String?
    public var inputTokensDelta: Int
    public var cachedInputTokensDelta: Int
    public var outputTokensDelta: Int
    public var reasoningOutputTokensDelta: Int
    public var estimatedCreditsDelta: Double?
    public var rateCardVersion: String?
    public var source: UsageEventSource

    public init(
        id: UUID = UUID(),
        accountAlias: String? = nil,
        threadID: String? = nil,
        taskTitleMasked: String? = nil,
        eventTime: Date = Date(),
        model: String? = nil,
        inputTokensDelta: Int = 0,
        cachedInputTokensDelta: Int = 0,
        outputTokensDelta: Int = 0,
        reasoningOutputTokensDelta: Int = 0,
        estimatedCreditsDelta: Double? = nil,
        rateCardVersion: String? = nil,
        source: UsageEventSource
    ) {
        self.id = id
        self.accountAlias = accountAlias
        self.threadID = threadID
        self.taskTitleMasked = taskTitleMasked
        self.eventTime = eventTime
        self.model = model
        self.inputTokensDelta = inputTokensDelta
        self.cachedInputTokensDelta = cachedInputTokensDelta
        self.outputTokensDelta = outputTokensDelta
        self.reasoningOutputTokensDelta = reasoningOutputTokensDelta
        self.estimatedCreditsDelta = estimatedCreditsDelta
        self.rateCardVersion = rateCardVersion
        self.source = source
    }
}

public enum UsageEventSource: String, Sendable {
    case localJSONL = "local_jsonl"
    case stateSQLite = "state_sqlite"
    case cliStatus = "cli_status"
    case officialAPI = "official_api"
    case importedReport = "imported_report"
    case manual
}

public extension UsageEvent {
    var inputMTokensDelta: Double {
        Double(inputTokensDelta) / 1_000_000
    }

    var cachedInputMTokensDelta: Double {
        Double(cachedInputTokensDelta) / 1_000_000
    }

    var outputMTokensDelta: Double {
        Double(outputTokensDelta) / 1_000_000
    }

    var reasoningOutputMTokensDelta: Double {
        Double(reasoningOutputTokensDelta) / 1_000_000
    }
}
