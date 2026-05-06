import Foundation

public struct CreditsCalculator: Sendable {
    public init() {}

    public func estimatedCredits(for usage: TokenUsage, rateCard: RateCard) -> Double {
        usage.inputMTokens * rateCard.inputCreditsPerM
            + usage.cachedInputMTokens * rateCard.cachedInputCreditsPerM
            + usage.outputMTokens * rateCard.outputCreditsPerM
    }
}
