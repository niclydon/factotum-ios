import Foundation
import UserNotifications
import UIKit

/// Manages push notification registration, handling, and reply actions.
///
/// Handles APNs device token registration with the server, notification
/// category setup (for inline replies), and deep-linking into conversations
/// when a notification is tapped.
@Observable
@MainActor
final class PushNotificationService: NSObject {

    static let shared = PushNotificationService()
    private let logger = Logger.shared

    // MARK: - State

    var isAuthorized = false
    var deviceToken: String?
    var pendingConversationId: String?
    var registrationError: String?
    /// Set when a PIE urgent notification is tapped — triggers new chat with insight.
    var pendingPIEInsight: PendingPIEInsight?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "push_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "push_enabled") }
    }

    /// The device name shown in the web UI delivery methods list.
    var registeredDeviceName: String {
        UIDevice.current.name
    }

    // MARK: - Notification Preferences (granular toggles)

    var insightsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "push_insights") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "push_insights") }
    }

    var remindersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "push_reminders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "push_reminders") }
    }

    var urgentAlertsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "push_urgent") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "push_urgent") }
    }

    var dailyBriefingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "push_briefing") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "push_briefing") }
    }

    var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "push_sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "push_sound") }
    }

    // MARK: - Constants

    static let replyCategory = "ARIA_REPLY"
    static let replyAction = "REPLY_ACTION"
    static let generalCategory = "ARIA_GENERAL"
    static let reviewCategory = "ARIA_REVIEW"

    // MARK: - Setup

    /// Register notification categories (reply action, general).
    func setupCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "Reply to ARIA",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a reply..."
        )

        let replyCategory = UNNotificationCategory(
            identifier: Self.replyCategory,
            actions: [replyAction],
            intentIdentifiers: [],
            options: [.allowInCarPlay]
        )

        let generalCategory = UNNotificationCategory(
            identifier: Self.generalCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // The ARIA_FEEDBACK category (Useful / Not Useful actions) was removed
        // 2026-09-25: its POST /api/proactive/insights/:id/feedback has no Nexus
        // handler. A push still tagged ARIA_FEEDBACK just renders without actions.

        let syncStaleCategory = UNNotificationCategory(
            identifier: SyncReminderScheduler.category,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let reviewCategory = UNNotificationCategory(
            identifier: Self.reviewCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            replyCategory,
            generalCategory,
            syncStaleCategory,
            reviewCategory,
        ])
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound, .providesAppNotificationSettings]
            )
            isAuthorized = granted
            if granted {
                isEnabled = true
                registrationError = nil
                // Register for remote notifications on the main thread
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                registrationError = "Notification permission was denied. Enable it in Settings > Notifications > ARIA."
            }
        } catch {
            registrationError = "Authorization failed: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    func checkAuthorization() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if isAuthorized && isEnabled {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func disconnect() {
        isEnabled = false
        isAuthorized = false
        registrationError = nil
        if let token = deviceToken {
            Task {
                try? await APIClient.shared.unregisterDeviceToken(token)
            }
        }
        deviceToken = nil
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    // MARK: - Notification Storage

    /// Store a notification in the on-device NotificationStore.
    private func storeNotification(_ content: UNNotificationContent) {
        let userInfo = content.userInfo
        let data = userInfo["data"] as? [String: Any]
        let insightId = data?["insight_id"] as? String ?? userInfo["insight_id"] as? String
        let conversationId = userInfo["conversation_id"] as? String
        let isPIEUrgent = insightId != nil && content.interruptionLevel == .timeSensitive

        NotificationStore.shared.addNotification(
            title: content.title,
            body: content.body,
            category: content.categoryIdentifier,
            conversationId: conversationId,
            isPIEUrgent: isPIEUrgent,
            insightContent: isPIEUrgent ? content.body : nil,
            insightId: insightId
        )
    }

    /// Store notification only if not already stored (for background-delivered notifications).
    private func storeNotificationIfNeeded(_ content: UNNotificationContent) {
        // Check if a notification with this exact title+body+time already exists recently
        let store = NotificationStore.shared
        let recentCutoff = Date().addingTimeInterval(-5)
        let alreadyStored = store.notifications.contains { n in
            n.title == content.title && n.body == content.body && n.receivedAt > recentCutoff
        }
        if !alreadyStored {
            storeNotification(content)
        }
    }

    // MARK: - Token Handling

    /// Called by AppDelegate when APNs token is received.
    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        logger.log("push", "Device token received: \(token.prefix(12))...")

        Task {
            do {
                let deviceName = UIDevice.current.name
                #if DEBUG
                let isSandbox = true
                #else
                let isSandbox = false
                #endif
                try await APIClient.shared.registerDeviceToken(token, deviceName: deviceName, isSandbox: isSandbox)
                logger.log("push", "Token registered with server for '\(deviceName)' (sandbox: \(isSandbox))")
                // The device-registration payload embeds this token. If APNs
                // delivered it after the launch registration already posted
                // (the first-launch race seen on build 143), the registration
                // fingerprint now differs and this re-posts in-session, so
                // factotum_devices shows push_token_present immediately
                // instead of from the next launch.
                DeviceRegistrationService.shared.registerIfNeeded()
            } catch {
                logger.logMinimal("push", "Token registration failed:", error.localizedDescription)
                registrationError = "Failed to register push token: \(error.localizedDescription)"
            }
        }
    }

    /// Called by AppDelegate when token registration fails.
    func handleRegistrationError(_ error: Error) {
        logger.logMinimal("push", "APNs registration failed:", error.localizedDescription)
        registrationError = "Push registration failed: \(error.localizedDescription)"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: @preconcurrency UNUserNotificationCenterDelegate {

    /// Called when a notification is received while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        let userInfo = content.userInfo
        let data = userInfo["data"] as? [String: Any]
        let urgency = data?["urgency"] as? String ?? userInfo["urgency"] as? String

        // Smart Notification Timing: check if non-urgent notification should be delayed
        if let urgency, urgency != "urgent" {
            let delay = NotificationTimingService.shared.recommendedDelay(urgency: urgency)
            if delay > 0 {
                // Schedule a local notification for later instead of showing now
                let delayedContent = UNMutableNotificationContent()
                delayedContent.title = content.title
                delayedContent.body = content.body
                delayedContent.categoryIdentifier = content.categoryIdentifier
                delayedContent.userInfo = userInfo
                if soundEnabled {
                    delayedContent.sound = .default
                }

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "delayed-\(UUID().uuidString)",
                    content: delayedContent,
                    trigger: trigger
                )
                try? await center.add(request)

                // Store but don't display now
                storeNotification(content)
                return []
            }
        }

        // Store notification for the notification center
        storeNotification(content)
        return [.banner, .sound, .badge]
    }

    /// Called when the user taps the app's notification-settings entry in iOS Settings.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        // Navigate to push settings in the app
        Task { @MainActor in
            DeepLinkManager.shared.pendingRoute = .pushSettings
        }
    }

    /// Called when the user interacts with a notification (tap or reply).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let userInfo = content.userInfo
        let conversationId = userInfo["conversation_id"] as? String

        // Store notification if it wasn't already stored (background delivery)
        storeNotificationIfNeeded(content)

        if response.actionIdentifier == Self.replyAction,
           let textResponse = response as? UNTextInputNotificationResponse {
            // User replied from the notification
            let replyText = textResponse.userText
            guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let originalTitle = content.title
            let originalBody = content.body
            let contextMessage = "ARIA sent me a notification:\n\"\(originalTitle): \(originalBody)\"\n\nMy reply: \(replyText)"

            do {
                try await APIClient.shared.sendReplyFromNotification(
                    conversationId: conversationId,
                    content: contextMessage
                )
            } catch {
                print("[PushNotificationService] Reply failed: \(error)")
            }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // Staleness nag tapped: refresh now and show freshness recover.
            if content.categoryIdentifier == SyncReminderScheduler.category {
                DeepLinkManager.shared.pendingRoute = .dataSources
                await SyncCoordinator.shared.runSweep(trigger: "reminder-tap")
                return
            }
            // User tapped the notification
            let data = userInfo["data"] as? [String: Any]

            // Review digest push tapped → open the Review tab (on the newest card when given).
            if (data?["type"] as? String) == "review-digest" {
                DeepLinkManager.shared.pendingReviewCardId = (data?["review_card_id"] as? String) ?? ""
                return
            }

            let insightId = data?["insight_id"] as? String ?? userInfo["insight_id"] as? String
            let isPIEUrgent = insightId != nil && content.interruptionLevel == .timeSensitive

            if isPIEUrgent, let conversationId {
                // PIE urgent: open the insight conversation with a pre-filled follow-up
                pendingPIEInsight = PendingPIEInsight(
                    conversationId: conversationId,
                    insightContent: content.body
                )
            } else if let conversationId {
                pendingConversationId = conversationId
            }
        }
    }
}

// MARK: - PIE Insight Deep Link

struct PendingPIEInsight {
    let conversationId: String
    let insightContent: String
}
