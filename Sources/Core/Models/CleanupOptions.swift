import Foundation

public struct CleanupOptions: Equatable, Sendable {
    public var clearUsageEvents: Bool
    public var clearSnapshots: Bool
    public var clearCollectorOffsets: Bool
    public var clearAlerts: Bool
    public var clearSwitchEvents: Bool
    public var clearAuditEvents: Bool
    public var clearAccounts: Bool
    public var clearKeychainSecrets: Bool
    public var resetSettings: Bool

    public init(
        clearUsageEvents: Bool = true,
        clearSnapshots: Bool = true,
        clearCollectorOffsets: Bool = true,
        clearAlerts: Bool = false,
        clearSwitchEvents: Bool = false,
        clearAuditEvents: Bool = false,
        clearAccounts: Bool = false,
        clearKeychainSecrets: Bool = false,
        resetSettings: Bool = false
    ) {
        self.clearUsageEvents = clearUsageEvents
        self.clearSnapshots = clearSnapshots
        self.clearCollectorOffsets = clearCollectorOffsets
        self.clearAlerts = clearAlerts
        self.clearSwitchEvents = clearSwitchEvents
        self.clearAuditEvents = clearAuditEvents
        self.clearAccounts = clearAccounts
        self.clearKeychainSecrets = clearKeychainSecrets
        self.resetSettings = resetSettings
    }
}
