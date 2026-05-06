import CodexQuotaCore
import Foundation

public struct SwitchProviderLaunch: Equatable, Sendable {
    public var providerName: String
    public var openedExternalFlow: Bool
    public var instructions: [String]

    public init(providerName: String, openedExternalFlow: Bool, instructions: [String]) {
        self.providerName = providerName
        self.openedExternalFlow = openedExternalFlow
        self.instructions = instructions
    }
}

public struct SwitchVerification: Equatable, Sendable {
    public var verified: Bool
    public var message: String

    public init(verified: Bool, message: String) {
        self.verified = verified
        self.message = message
    }
}

public protocol SwitchProvider: Sendable {
    var providerName: String { get }

    func launchSwitchFlow(from source: Account?, to target: Account) async throws -> SwitchProviderLaunch
    func verifySwitch(to target: Account, userConfirmedOfficialFlow: Bool) async throws -> SwitchVerification
}

public struct OfficialLoginSwitchProvider: SwitchProvider {
    public var providerName: String
    public var loginURL: URL
    private let openURL: @Sendable (URL) async -> Bool

    public init(
        providerName: String = "official_login",
        loginURL: URL = URL(string: "https://chatgpt.com/auth/login")!,
        openURL: @escaping @Sendable (URL) async -> Bool = { _ in false }
    ) {
        self.providerName = providerName
        self.loginURL = loginURL
        self.openURL = openURL
    }

    public func launchSwitchFlow(from source: Account?, to target: Account) async throws -> SwitchProviderLaunch {
        let opened = await openURL(loginURL)
        let sourceAlias = source?.alias ?? "未设置"
        let factorSummary = verificationSummary(for: target)
        let credentialSummary = credentialSummary(for: target)
        return SwitchProviderLaunch(
            providerName: providerName,
            openedExternalFlow: opened,
            instructions: [
                "当前账号：\(sourceAlias)",
                "目标账号：\(target.alias)",
                credentialSummary,
                factorSummary,
                "使用官方登录或账号选择流程完成切换。",
                "本应用不会读取、复制或替换 Codex auth 文件。"
            ].filter { !$0.isEmpty }
        )
    }

    public func verifySwitch(to target: Account, userConfirmedOfficialFlow: Bool) async throws -> SwitchVerification {
        if userConfirmedOfficialFlow {
            return SwitchVerification(
                verified: true,
                message: "用户确认官方流程已切换到：\(target.alias)"
            )
        }
        return SwitchVerification(
            verified: false,
            message: "用户未确认官方流程完成"
        )
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
}
