import UIKit

/// Carries the non-Sendable completion handler across the @Sendable Task
/// boundary onto the main actor. Safe: the system gives us exclusive ownership
/// for this delivery.
private struct UncheckedSendableHandler: @unchecked Sendable {
    let value: (UIBackgroundFetchResult) -> Void
}

/// AppDelegate adapter for push notifications, Quick Actions, and Spotlight continuations.
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        // App-side "unit test" for the mobile-write contract (no XCTest target in
        // this repo — see docs/aria-ios-nexus-release-verification.md §4). Traps
        // at debug launch if the idempotency-key or retry classification regresses.
        MobileWriteContract.runSelfCheck()
        MobileErrorTelemetry.runSelfCheck()
        ChatEventContract.runSelfCheck()
        ContractFixtures.runSelfCheck()
        DeviceSource.runSelfCheck()
        ReviewContract.runSelfCheck()
        MobileEstateContract.runSelfCheck()
        DeviceEventFactory.runSelfCheck()
        DeviceEventQueueState.runSelfCheck()
        DeviceEventSync.runSelfCheck()
        HealthRecordMapping.runSelfCheck()
        HealthFilePayloads.runSelfCheck()
        // Async: HealthKit validates the authorization sets out of process. A bad set
        // crashes here, so "all passed" never prints and the runner fails.
        Task { @MainActor in
            await HealthKitService.runAuthorizationSelfCheck()
            print("[selfcheck] all passed")
        }
        #endif
        SyncCoordinator.registerBackgroundTask()
        LensService.registerBackgroundTask()
        // Background (content-available) pushes need an APNs token but no banner
        // permission. Register unconditionally so silent sync-wakes work even
        // when the user has declined visible notifications.
        application.registerForRemoteNotifications()
        Task { @MainActor in
            HealthKitService.shared.checkAuthorization()
        }
        return true
    }

    // MARK: - Push Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationError(error)
        }
    }

    // MARK: - Silent (background) push

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Only handle our sync-wake background pushes; ignore everything else so
        // this path never interferes with alert pushes.
        let data = userInfo["data"] as? [String: Any]
        let type = data?["type"] as? String ?? userInfo["type"] as? String
        guard type == "sync-wake" else {
            completionHandler(.noData)
            return
        }

        let box = UncheckedSendableHandler(value: completionHandler)
        Task { @MainActor in
            await SyncCoordinator.shared.runSweep(trigger: "silent-push")
            box.value(.newData)
        }
    }

    // MARK: - Quick Actions (Home Screen 3D Touch / Long Press)

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Handle quick action if app was launched from one
        if let shortcutItem = options.shortcutItem,
           let action = DeepLinkManager.QuickAction(rawValue: shortcutItem.type) {
            Task { @MainActor in
                DeepLinkManager.shared.handleQuickAction(action)
            }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// SceneDelegate handles Quick Actions when the app is already running.
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let action = DeepLinkManager.QuickAction(rawValue: shortcutItem.type) {
            Task { @MainActor in
                DeepLinkManager.shared.handleQuickAction(action)
            }
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}
