import CodexQuotaCore
import XCTest

final class QuotaStatusPresenterTests: XCTestCase {
    func testMenuBarTitleShowsRemainingPercentages() {
        let presenter = QuotaStatusPresenter()
        let title = presenter.menuBarTitle(for: .mockHealthy)

        XCTAssertEqual(title, "Cdx 5H 55% 1W 82%")
    }

    func testMenuBarTitleShowsRefreshingWhenSnapshotIsStaleAndEmpty() {
        let presenter = QuotaStatusPresenter()
        let title = presenter.menuBarTitle(for: .mockRefreshing)

        XCTAssertEqual(title, "Cdx 刷新中...")
    }

    func testMenuBarTitleShowsUnconfiguredState() {
        let presenter = QuotaStatusPresenter()
        let title = presenter.menuBarTitle(for: .unconfigured)

        XCTAssertEqual(title, "Cdx 未设置")
    }

    func testMTokenFormattingFollowsProductPrecisionRules() {
        let presenter = QuotaStatusPresenter()

        XCTAssertEqual(presenter.formatMTokens(0.0004), "<0.001M")
        XCTAssertEqual(presenter.formatMTokens(1.2345), "1.234M")
        XCTAssertEqual(presenter.formatMTokens(12.345), "12.35M")
        XCTAssertEqual(presenter.formatMTokens(123.45), "123.5M")
    }
}
