import CodexQuotaCore
import CodexQuotaSwitch
import XCTest

final class OfficialLoginSwitchProviderTests: XCTestCase {
    func testLaunchInstructionsIncludeCredentialAndVerificationHints() async throws {
        let provider = OfficialLoginSwitchProvider(
            openURL: { _ in true }
        )
        let target = Account(
            alias: "target",
            loginIdentifierMasked: "owner@example.com",
            passwordRequired: true,
            verificationMethods: [.emailOTP, .authenticatorTOTP],
            verificationHint: "邮箱验证码 + Google Authenticator"
        )

        let launch = try await provider.launchSwitchFlow(from: nil, to: target)

        XCTAssertTrue(launch.instructions.contains("登录标识：owner@example.com，需要密码"))
        XCTAssertTrue(launch.instructions.contains("二次验证：邮箱验证码 + Authenticator 动态码（邮箱验证码 + Google Authenticator）"))
    }
}
