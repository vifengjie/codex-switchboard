import CodexQuotaCore
import CodexQuotaStorage
import Foundation
import UserNotifications

struct QuotaNotificationCoordinator {
    private let policy = QuotaAlertPolicy()

    func deliverIfNeeded(snapshot: QuotaSnapshot, store: SQLiteStore) async {
        do {
            let settings = try SQLiteSettingsRepository(store: store).ensureDefaultSettings()
            guard let request = policy.notificationRequest(for: snapshot, settings: settings) else {
                return
            }

            let repository = SQLiteAlertEventRepository(store: store)
            let lastAttempt = try repository.lastEvent(dedupeKey: request.dedupeKey)
            let lastAttemptAt = lastAttempt?.deliveredAt ?? lastAttempt?.createdAt
            if policy.shouldSuppress(lastDeliveredAt: lastAttemptAt, settings: settings) {
                return
            }

            guard notificationsAreAvailableInCurrentProcess() else {
                try repository.record(
                    AlertEvent(
                        alertType: request.status,
                        accountAlias: snapshot.accountAlias,
                        dedupeKey: request.dedupeKey,
                        snapshotCapturedAt: snapshot.capturedAt,
                        result: .failed,
                        message: "notifications unavailable in non-bundled run"
                    )
                )
                return
            }

            let authorized = await requestAuthorization()
            guard authorized else {
                try repository.record(
                    AlertEvent(
                        alertType: request.status,
                        accountAlias: snapshot.accountAlias,
                        dedupeKey: request.dedupeKey,
                        snapshotCapturedAt: snapshot.capturedAt,
                        result: .failed,
                        message: "notification authorization denied"
                    )
                )
                return
            }

            try await deliver(request)
            try repository.record(
                AlertEvent(
                    alertType: request.status,
                    accountAlias: snapshot.accountAlias,
                    dedupeKey: request.dedupeKey,
                    snapshotCapturedAt: snapshot.capturedAt,
                    deliveredAt: Date(),
                    result: .delivered,
                    message: request.body
                )
            )
        } catch {
            NSLog("Codex Quota Manager notification failed: \(error)")
        }
    }

    private func notificationsAreAvailableInCurrentProcess() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension == "app"
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func deliver(_ request: QuotaNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let notificationRequest = UNNotificationRequest(
            identifier: request.dedupeKey,
            content: content,
            trigger: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(notificationRequest) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
