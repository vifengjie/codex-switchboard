import CodexQuotaCore
import XCTest

final class RateCardManagerTests: XCTestCase {
    func testDecodesCatalogAndEstimatesCreditsByModel() throws {
        let json = """
            {
              "version": "fixture-2026-05-03",
              "source_url": "https://example.com/rate-card",
              "models": [
                {
                  "model": "mock-codex",
                  "input_credits_per_m": 10,
                  "cached_input_credits_per_m": 2,
                  "output_credits_per_m": 40
                },
                {
                  "model": "mock-fast",
                  "input_credits_per_m": 1,
                  "cached_input_credits_per_m": 0.2,
                  "output_credits_per_m": 4
                }
              ]
            }
            """

        let catalog = try RateCardManager.decodeCatalog(from: json)
        let manager = RateCardManager(catalog: catalog)
        let usage = TokenUsage(inputTokens: 2_000_000, cachedInputTokens: 1_000_000, outputTokens: 500_000)

        let estimated = try XCTUnwrap(manager.estimatedCredits(for: usage, model: "MOCK-CODEX"))

        XCTAssertEqual(estimated.credits, 42)
        XCTAssertEqual(estimated.rateCardVersion, "fixture-2026-05-03")
        XCTAssertNil(manager.estimatedCredits(for: usage, model: "unknown-model"))
    }
}
