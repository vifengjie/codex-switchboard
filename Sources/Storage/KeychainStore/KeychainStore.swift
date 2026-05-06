import Foundation

public struct KeychainStore: Sendable {
    public init() {}

    public func saveSecret(_ secret: Data, service: String, account: String) throws {
        // M0 scaffold only. M4 will implement Security.framework Keychain calls.
        _ = secret
        _ = service
        _ = account
    }
}
