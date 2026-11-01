import Foundation
import UserNotifications

/// Owns exactly one local notification — the rolling "sync has gone stale" nag.
/// Every successful sync sweep calls `rearm(from:)`, which removes the pending
/// nag and reschedules it for `threshold` seconds later. As long as some sync
/// keeps succeeding, the nag's fire date keeps moving forward and it never
/// actually fires. It only surfaces when sync has been silent past the
/// threshold — the "I forgot to open the app" case.
@MainActor
@Observable
final class SyncReminderScheduler {
    static let shared = SyncReminderScheduler()

    /// Fixed request id so each rearm replaces (not duplicates) the pending nag.
    static let identifier = "sync-staleness-nag"
    /// Notification category id, also matched in PushNotificationService tap handling.
    static let category = "ARIA_SYNC_STALE"

    /// How long sync may be silent before the nag fires.
    private let threshold: TimeInterval = 14 * 60 * 60
    private let center: any NotificationScheduling
    private let enabledKey = "sync_reminder_enabled"
    private let logger = Logger.shared

    /// Master toggle, persisted. Default ON.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    init(center: any NotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
        self.isEnabled = UserDefaults.standard.object(forKey: "sync_reminder_enabled") as? Bool ?? true
    }

    /// Pure, inspectable core: seconds-from-now at which the nag should fire,
    /// given the last successful sync. Clamped to a positive minimum because
    /// UNTimeIntervalNotificationTrigger requires interval > 0.
    static func fireInterval(lastSync: Date, now: Date, threshold: TimeInterval) -> TimeInterval {
        let target = lastSync.addingTimeInterval(threshold)
        return max(60, target.timeIntervalSince(now))
    }

    /// Replace the pending nag with one armed for `threshold` after `date`.
    func rearm(from date: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "ARIA is falling behind"
        content.body = "Open ARIA to keep Health, Motion and Music syncing."
        content.categoryIdentifier = Self.category
        content.sound = nil

        let interval = Self.fireInterval(lastSync: date, now: Date(), threshold: threshold)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)

        Task { [center, logger] in
            do {
                try await center.add(request)
                logger.logVerbose("sync", "Staleness nag rearmed for +\(Int(interval / 3600))h")
            } catch {
                logger.logMinimal("sync", "Failed to arm staleness nag:", error.localizedDescription)
            }
        }
    }

    /// Clear the pending nag (sign-out, or toggle off).
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        logger.logVerbose("sync", "Staleness nag cancelled")
    }
}
