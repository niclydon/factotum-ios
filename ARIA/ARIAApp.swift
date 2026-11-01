import SwiftUI
import SwiftData
import Combine
import CoreSpotlight

@main
struct ARIAApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager = AuthManager()
    @State private var healthKitService = HealthKitService.shared
    @State private var locationService = LocationService()
    @State private var motionService = MotionService.shared
    @State private var musicService = MusicKitService.shared
    @State private var biometricLock = BiometricLockService()
    @State private var syncCoordinator = SyncCoordinator.shared
    private var pushService = PushNotificationService.shared
    private var deepLinkManager = DeepLinkManager.shared
    private var notificationStore = NotificationStore.shared
    private var bootstrapStore = BootstrapStore.shared
    private var freshnessStore = FreshnessStore.shared
    private var estateStore = EstateStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(healthKitService)
                .environment(locationService)
                .environment(motionService)
                .environment(musicService)
                .environment(pushService)
                .environment(deepLinkManager)
                .environment(notificationStore)
                .environment(biometricLock)
                .environment(syncCoordinator)
                .environment(bootstrapStore)
                .environment(ReviewStore.shared)
                .environment(TodayStore.shared)
                .environment(freshnessStore)
                .environment(estateStore)
                .onChange(of: scenePhase) { _, phase in
                    // Control Center controls (4.0 W6) leave the tab they
                    // want in the App Group defaults.
                    if phase == .active,
                       let tab = UserDefaults(suiteName: "group.com.example.factotum")?.string(forKey: "factotum_pending_tab") {
                        UserDefaults(suiteName: "group.com.example.factotum")?.removeObject(forKey: "factotum_pending_tab")
                        deepLinkManager.pendingTab = tab
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        if identifier.hasPrefix("replay-day:") {
                            deepLinkManager.pendingReplayDateString = String(identifier.dropFirst("replay-day:".count))
                            deepLinkManager.pendingTab = "replay"
                        } else {
                            deepLinkManager.handleSpotlightConversation(id: identifier)
                        }
                    }
                }
                .task {
                    // Reset biometric lock state on fresh launch (never start locked)
                    biometricLock.isLocked = false

                    // Set up push notification delegate and categories (safe without auth)
                    UNUserNotificationCenter.current().delegate = pushService
                    pushService.setupCategories()

                    // Only check and sync services if authenticated
                    guard authManager.isAuthenticated else { return }
                    startServices()
                }
                .onChange(of: authManager.isAuthenticated) { old, isAuthenticated in
                    if isAuthenticated {
                        startServices()
                        // Enable biometric on first login (not on app restart with stored token)
                        if old == false {
                            biometricLock.enableAfterLogin()
                        }
                    } else {
                        // Session lapse (e.g. JWT expiry) must NOT wipe the persisted
                        // per-source enables — auto-SSO re-login should resume all syncs.
                        // The destructive reset runs only on an explicit sign-out below.
                        biometricLock.disable()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ariaDidLogout)) { _ in
                    Task { await disconnectAllServices() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Handle biometric lock and command polling
                    if newPhase == .background || newPhase == .inactive {
                        biometricLock.appDidEnterBackground()
                        if authManager.isAuthenticated {
                            syncCoordinator.scheduleNext()
                        }
                    } else if newPhase == .active {
                        if authManager.isAuthenticated && biometricLock.isEnabled {
                            biometricLock.appWillEnterForeground()
                        }
                    }

                    guard newPhase == .active, authManager.isAuthenticated else { return }
                    if healthKitService.isEnabled {
                        Task { await healthKitService.sync() }
                    }
                    if locationService.isEnabled {
                        Task { await locationService.sync() }
                    }
                    if motionService.isEnabled {
                        Task { await motionService.sync() }
                    }
                    if musicService.isEnabled {
                        Task { await musicService.sync() }
                    }
                    Task { await DeviceEventSync.shared.flush(budget: 20) }
                    if HealthFilesSync.shared.isEnabled { Task { await HealthFilesSync.shared.sync() } }
                    DeviceRegistrationService.shared.registerIfNeeded()
                    UpdateChecker.shared.refreshIfNeeded()
                }
        }
        .modelContainer(for: [Conversation.self, ChatMessage.self])
    }

    /// Disconnect all integrations on logout. `async` and awaited by its caller
    /// (not a fire-and-forget `Task`) so the device-event queue is provably empty
    /// before this returns — a detached, un-awaited clear left a window where a
    /// fast re-login could let the DEPARTING user's queued events get POSTed
    /// under the NEW session's auth token.
    private func disconnectAllServices() async {
        healthKitService.disconnect()
        locationService.disconnect()
        motionService.disconnect()
        musicService.disconnect()
        pushService.disconnect()
        await DeviceEventSync.shared.clearQueue()
        HealthFilesSync.shared.disconnect()
        LensService.shared.stopObserving()
        SpotlightIndexer.removeAll()
        WidgetDataService.clearAll()
    }

    /// Check authorization and kick off syncs in background.
    /// Called during splash screen so everything is ready when chat UI appears.
    private func startServices() {
        // Migrate keychain items to shared group (one-time, for Watch app support)
        KeychainManager.migrateToSharedGroup()

        // Capabilities bootstrap (OB-52301) — fire-and-forget; never blocks chat.
        bootstrapStore.refreshIfNeeded()
        // Server-side freshness aggregate (OB-52302) — reconcile with local SyncFreshness.
        freshnessStore.refreshIfNeeded()

        // Factotum 3.2: device citizenship (Phase 2) + Ad Hoc update awareness.
        DeviceRegistrationService.shared.registerIfNeeded()
        UpdateChecker.shared.refreshIfNeeded()

        // Push token registration (fast, important)
        pushService.checkAuthorization()

        // Auth checks (lightweight, no network)
        healthKitService.checkAuthorization()
        locationService.checkAuthorization()
        // Geofencing retired 2026-09-25 (no Nexus /api/geofences*): stop any
        // OS-persisted regions an older build registered.
        locationService.retireLegacyGeofenceRegions()
        motionService.checkAvailability()
        musicService.checkAuthorization()
        LensService.shared.checkAuthorization()

        // Syncs in background — staggered so they don't compete
        Task {
            if musicService.isEnabled { Task { await musicService.sync() } }

            // Health is heaviest — give others a head start
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if healthKitService.isEnabled { Task { await healthKitService.sync() } }
        }

        // Ensure a background-refresh request exists even if the app is never backgrounded.
        syncCoordinator.scheduleNext()
    }
}
