import CodexQuotaCore
import XCTest

final class QuotaEngineTests: XCTestCase {
    func testRemainingPercentIsClampedToDisplayRange() {
        let engine = QuotaEngine()

        XCTAssertEqual(engine.remainingPercent(fromUsedPercent: 45), 55)
        XCTAssertEqual(engine.remainingPercent(fromUsedPercent: -20), 100)
        XCTAssertEqual(engine.remainingPercent(fromUsedPercent: 120), 0)
        XCTAssertNil(engine.remainingPercent(fromUsedPercent: nil))
    }
}
