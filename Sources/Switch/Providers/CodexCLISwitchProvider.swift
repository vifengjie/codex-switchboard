import CodexQuotaCore
import Foundation

public enum CodexCLISwitchProviderError: LocalizedError, Equatable, Sendable {
    case codexExecutableMissing(String)
    case terminalLaunchFailed
    case scriptWriteFailed(String)
    case loginStatusFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .codexExecutableMissing(path):
            return "未找到 Codex CLI：\(path)"
        case .terminalLaunchFailed:
            return "无法启动 Codex 登录终端"
        case let .scriptWriteFailed(message):
            return "写入登录脚本失败：\(message)"
        case let .loginStatusFailed(message):
            return "读取 Codex 登录状态失败：\(message)"
        }
    }
}

public struct CodexCLISwitchProvider: SwitchProvider {
    public var providerName: String
    public var codexExecutablePath: String
    private let openScript: @Sendable (URL) async -> Bool
    private let runCommand: @Sendable (String, [String]) async throws -> CommandResult
    private let temporaryDirectory: @Sendable () -> URL

    public init(
        providerName: String = "codex_cli_device_auth",
        codexExecutablePath: String = "/Applications/Codex.app/Contents/Resources/codex",
        openScript: @escaping @Sendable (URL) async -> Bool,
        runCommand: @escaping @Sendable (String, [String]) async throws -> CommandResult = Self.runCommand,
        temporaryDirectory: @escaping @Sendable () -> URL = { FileManager.default.temporaryDirectory }
    ) {
        self.providerName = providerName
        self.codexExecutablePath = codexExecutablePath
        self.openScript = openScript
        self.runCommand = runCommand
        self.temporaryDirectory = temporaryDirectory
    }

    public func launchSwitchFlow(from source: Account?, to target: Account) async throws -> SwitchProviderLaunch {
        guard FileManager.default.isExecutableFile(atPath: codexExecutablePath) else {
            throw CodexCLISwitchProviderError.codexExecutableMissing(codexExecutablePath)
        }

        let scriptURL = try makeLoginScript(for: target, source: source)
        let opened = await openScript(scriptURL)
        guard opened else {
            throw CodexCLISwitchProviderError.terminalLaunchFailed
        }

        return SwitchProviderLaunch(
            providerName: providerName,
            openedExternalFlow: true,
            instructions: [
                "已打开 Codex CLI 登录终端",
                "目标账号：\(target.alias)",
                credentialSummary(for: target),
                verificationSummary(for: target),
                "终端会先执行 Codex logout，再进入 codex login --device-auth。",
                "请在官方流程中选择目标账号，完成后回到本窗口确认。"
            ].filter { !$0.isEmpty }
        )
    }

    public func verifySwitch(to target: Account, userConfirmedOfficialFlow: Bool) async throws -> SwitchVerification {
        guard userConfirmedOfficialFlow else {
            return SwitchVerification(
                verified: false,
                message: "用户未确认 Codex CLI 登录流程完成"
            )
        }

        let result: CommandResult
        do {
            result = try await runCommand(codexExecutablePath, ["login", "status"])
        } catch {
            throw CodexCLISwitchProviderError.loginStatusFailed(error.localizedDescription)
        }

        let statusText = [result.standardOutput, result.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.exitCode == 0, statusText.contains("Logged in") else {
            return SwitchVerification(
                verified: false,
                message: statusText.isEmpty ? "Codex 仍未处于已登录状态" : statusText
            )
        }

        return SwitchVerification(
            verified: true,
            message: "Codex CLI 登录状态正常：\(statusText)"
        )
    }

    private func makeLoginScript(for target: Account, source: Account?) throws -> URL {
        let scriptURL = temporaryDirectory()
            .appendingPathComponent("codex-switch-\(target.id.uuidString)")
            .appendingPathExtension("command")

        let sourceAlias = source?.alias ?? "未设置"
        let lines = [
            "#!/bin/zsh",
            "echo \"Codex account switch\"",
            "echo \"Current account: \(escapeForDoubleQuotedShell(sourceAlias))\"",
            "echo \"Target account: \(escapeForDoubleQuotedShell(target.alias))\"",
            credentialSummary(for: target).isEmpty ? nil : "echo \"\(escapeForDoubleQuotedShell(credentialSummary(for: target)))\"",
            verificationSummary(for: target).isEmpty ? nil : "echo \"\(escapeForDoubleQuotedShell(verificationSummary(for: target)))\"",
            "echo",
            "\"\(codexExecutablePath)\" logout || true",
            "\"\(codexExecutablePath)\" login --device-auth",
            "echo",
            "echo \"Return to Codex Quota Manager after login completes.\"",
            "exec /bin/zsh -l"
        ].compactMap { $0 }.joined(separator: "\n")

        do {
            try lines.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            return scriptURL
        } catch {
            throw CodexCLISwitchProviderError.scriptWriteFailed(error.localizedDescription)
        }
    }

    private func credentialSummary(for account: Account) -> String {
        var parts: [String] = []
        if let loginIdentifierMasked = account.loginIdentifierMasked, !loginIdentifierMasked.isEmpty {
            parts.append("登录标识：\(loginIdentifierMasked)")
        }
        if account.passwordRequired {
            parts.append("需要密码")
        }
        return parts.joined(separator: "，")
    }

    private func verificationSummary(for account: Account) -> String {
        guard !account.verificationMethods.isEmpty else {
            return ""
        }
        let methodSummary = account.verificationMethods.map { method in
            switch method {
            case .emailOTP:
                return "邮箱验证码"
            case .authenticatorTOTP:
                return "Authenticator 动态码"
            case .smsOTP:
                return "短信验证码"
            case .unknown:
                return "额外验证码"
            }
        }.joined(separator: " + ")

        if let verificationHint = account.verificationHint, !verificationHint.isEmpty {
            return "二次验证：\(methodSummary)（\(verificationHint)）"
        }
        return "二次验证：\(methodSummary)"
    }

    private func escapeForDoubleQuotedShell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    public struct CommandResult: Equatable, Sendable {
        public var exitCode: Int32
        public var standardOutput: String
        public var standardError: String

        public init(exitCode: Int32, standardOutput: String, standardError: String) {
            self.exitCode = exitCode
            self.standardOutput = standardOutput
            self.standardError = standardError
        }
    }

    public static func runCommand(_ launchPath: String, _ arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                continuation.resume(
                    returning: CommandResult(
                        exitCode: process.terminationStatus,
                        standardOutput: output,
                        standardError: error
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
