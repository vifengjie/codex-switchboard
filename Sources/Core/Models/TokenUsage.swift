import Foundation

public struct TokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningOutputTokens: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }

    public static let zero = TokenUsage()
}

public extension TokenUsage {
    var inputMTokens: Double {
        Double(inputTokens) / 1_000_000
    }

    var cachedInputMTokens: Double {
        Double(cachedInputTokens) / 1_000_000
    }

    var outputMTokens: Double {
        Double(outputTokens) / 1_000_000
    }

    var reasoningOutputMTokens: Double {
        Double(reasoningOutputTokens) / 1_000_000
    }
}
