import CodexQuotaCore
import CodexQuotaSwitch
import Foundation
import XCTest

final class CodexCLISwitchProviderTests: XCTestCase {
    func testLaunchCreatesTerminalScriptAndInstructions() async throws {
        let tempDirectory = makeTemporaryDirectory()
        let executablePath = try makeFakeExecutable(in: tempDirectory)
        let recorder = ScriptRecorder()

        let provider = CodexCLISwitchProvider(
            codexExecutablePath: executablePath.path,
            openScript: { scriptURL in
                await recorder.record(scriptURL)
                return true
            },
            runCommand: { _, _ in
                CodexCLISwitchProvider.CommandResult(exitCode: 0, standardOutput: "", standardError: "")
            },
            temporaryDirectory: { tempDirectory }
        )
        let target = Account(
            alias: "target",
            loginIdentifierMasked: "a***@example.com",
            passwordRequired: true,
            verificationMethods: [.emailOTP],
            verificationHint: "验证码发到邮箱"
        )

        let launch = try await provider.launchSwitchFlow(from: Account(alias: "source"), to: target)

        XCTAssertEqual(launch.providerName, "codex_cli_device_auth")
        XCTAssertTrue(launch.openedExternalFlow)
        XCTAssertEqual(launch.instructions.contains("已打开 Codex CLI 登录终端"), true)
        XCTAssertEqual(launch.instructions.contains("终端会先执行 Codex logout，再进入 codex login --device-auth。"), true)
        let recordedScriptURL = await recorder.value()
        let scriptURL = try XCTUnwrap(recordedScriptURL)
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("logout || true"))
        XCTAssertTrue(script.contains("login --device-auth"))
    }

    func testVerifySwitchUsesCodexLoginStatus() async throws {
        let tempDirectory = makeTemporaryDirectory()
        let executablePath = try makeFakeExecutable(in: tempDirectory)
        let provider = CodexCLISwitchProvider(
            codexExecutablePath: executablePath.path,
            openScript: { _ in true },
            runCommand: { _, arguments in
                XCTAssertEqual(arguments, ["login", "status"])
                return CodexCLISwitchProvider.CommandResult(
                    exitCode: 0,
                    standardOutput: "Logged in using ChatGPT",
                    standardError: ""
                )
            },
            temporaryDirectory: { tempDirectory }
        )

        let verification = try await provider.verifySwitch(
            to: Account(alias: "target"),
            userConfirmedOfficialFlow: true
        )

        XCTAssertTrue(verification.verified)
        XCTAssertEqual(verification.message, "Codex CLI 登录状态正常：Logged in using ChatGPT")
    }

    func testVerifySwitchFailsWhenStatusIsNotLoggedIn() async throws {
        let tempDirectory = makeTemporaryDirectory()
        let executablePath = try makeFakeExecutable(in: tempDirectory)
        let provider = CodexCLISwitchProvider(
            codexExecutablePath: executablePath.path,
            openScript: { _ in true },
            runCommand: { _, _ in
                CodexCLISwitchProvider.CommandResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "Not logged in"
                )
            },
            temporaryDirectory: { tempDirectory }
        )

        let verification = try await provider.verifySwitch(
            to: Account(alias: "target"),
            userConfirmedOfficialFlow: true
        )

        XCTAssertFalse(verification.verified)
        XCTAssertEqual(verification.message, "Not logged in")
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFakeExecutable(in directory: URL) throws -> URL {
        let executableURL = directory.appendingPathComponent("codex")
        try "#!/bin/zsh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return executableURL
    }
}

private actor ScriptRecorder {
    private var scriptURL: URL?

    func record(_ url: URL) {
        scriptURL = url
    }

    func value() -> URL? {
        scriptURL
    }
}
