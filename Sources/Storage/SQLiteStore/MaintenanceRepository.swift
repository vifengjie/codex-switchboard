import CodexQuotaCore
import Foundation
import SQLite3

public struct SQLiteMaintenanceRepository: Sendable {
    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func performCleanup(
        _ options: CleanupOptions,
        accountRepository: SQLiteAccountRepository,
        keychainStore: KeychainStore
    ) throws {
        let keychainRefs: [String] = if options.clearAccounts && options.clearKeychainSecrets {
            try accountRepository.listAccounts().compactMap(\.keychainRef)
        } else {
            []
        }

        try store.withDatabase { db in
            if options.clearUsageEvents {
                try executeDelete(db, table: "usage_events")
            }
            if options.clearSnapshots {
                try executeDelete(db, table: "quota_snapshots")
            }
            if options.clearCollectorOffsets {
                try executeDelete(db, table: "collector_offsets")
            }
            if options.clearAlerts {
                try executeDelete(db, table: "alert_events")
            }
            if options.clearSwitchEvents {
                try executeDelete(db, table: "switch_events")
            }
            if options.clearAuditEvents {
                try executeDelete(db, table: "audit_events")
            }
            if options.clearAccounts {
                try executeDelete(db, table: "accounts")
            }
            if options.resetSettings {
                try executeDelete(db, table: "app_settings")
            }
        }

        if options.clearAccounts && options.clearKeychainSecrets {
            for reference in keychainRefs {
                _ = try? keychainStore.deleteSecret(reference: reference)
            }
        }
    }

    private func executeDelete(_ db: OpaquePointer, table: String) throws {
        let sql = "DELETE FROM \(table)"
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.stepFailed(message)
        }
    }
}
