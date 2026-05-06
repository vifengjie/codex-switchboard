import Foundation

public enum CodexQuotaStoragePaths {
    public static func defaultDatabaseURL() throws -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL
            .appendingPathComponent("Codex Quota Manager", isDirectory: true)
            .appendingPathComponent("quota-manager.sqlite")
    }
}
