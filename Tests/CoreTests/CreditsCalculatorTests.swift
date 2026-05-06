import CodexQuotaCore
import XCTest

final class CreditsCalculatorTests: XCTestCase {
    func testEstimatedCreditsUsesMillionTokenUnits() {
        let usage = TokenUsage(
            inputTokens: 2_000_000,
            cachedInputTokens: 4_000_000,
            outputTokens: 1_000_000
        )
        let rateCard = RateCard(
            model: "mock-codex",
            version: "fixture-2026-05-03",
            inputCreditsPerM: 10,
            cachedInputCreditsPerM: 2,
            outputCreditsPerM: 40
        )

        let credits = CreditsCalculator().estimatedCredits(for: usage, rateCard: rateCard)

        XCTAssertEqual(credits, 68)
    }
}
