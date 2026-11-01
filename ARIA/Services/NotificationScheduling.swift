import UserNotifications

/// Narrow seam over UNUserNotificationCenter so SyncReminderScheduler's
/// scheduling logic can be exercised without the live notification system.
@MainActor
protocol NotificationScheduling {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

// UNUserNotificationCenter already provides both members with these exact
// signatures (the async `add` is the system-generated concurrency overload),
// so conformance is declaration-only.
extension UNUserNotificationCenter: NotificationScheduling {}
