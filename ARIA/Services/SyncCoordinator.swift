import Foundation
import BackgroundTasks

/// Carries a non-Sendable BGTask across the BGTaskScheduler @Sendable handler
/// boundary onto the main actor. Safe because the system hands us exclusive
/// ownership of the task for the duration of this launch.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

/// Owns the app's background-refresh lifecycle: registers one BGAppRefreshTask,
/// schedules opportunistic wakes, and runs a bounded sweep over enabled sync
/// sources. Self-contained — does not depend on SwiftUI view state, because a
/// background launch may fire the handler before the UI initializes.
@Observable
@MainActor
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    nonisolated static let taskIdentifier = "com.example.factotum.refresh"

    /// iOS treats this as a floor, not a guarantee. Real cadence is iOS-decided.
    private let refreshInterval: TimeInterval = 2 * 60 * 60
    /// Total wall-clock budget for one sweep, well under the ~30s BGAppRefresh limit.
    private let sweepBudget: TimeInterval = 25

    private let logger = Logger.shared

    // Coordinator participants — the shared singletons the Settings UI observes, so a
    // successful background sweep updates the SAME instances the UI reads
    // (`isAuthorized`/`isAvailable`/`lastSyncDate`), rather than throwaway copies.
    // DeviceEventSync goes first: it is cheap and its events are the most
    // time-sensitive. Location is intentionally excluded — it has its own background
    // monitoring (visits + significant-change).
    private var participants: [any BackgroundSyncable] {
        [DeviceEventSync.shared, HealthKitService.shared, MotionService.shared, MusicKitService.shared, HealthFilesSync.shared, LensService.shared]
    }

    private(set) var snapshot = SyncFreshness.load()
    private var isSweeping = false

    private init() {}

    // MARK: - Registration (must run before app finishes launching)

    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            let box = UncheckedSendableBox(value: refreshTask)
            Task { @MainActor in
                SyncCoordinator.shared.handle(task: box.value)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        // submit() is deprecated in iOS 27; submitTaskRequest reports
        // failure through its completion handler instead of throwing.
        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            if let error {
                self.logger.logMinimal("sync", "Failed to schedule background refresh:", error.localizedDescription)
            } else {
                self.logger.logVerbose("sync", "Scheduled next background refresh")
            }
        }
    }

    // MARK: - Sweep

    private func handle(task: BGAppRefreshTask) {
        let sweep = Task { @MainActor in
            await runSweep(trigger: "bg-refresh")
        }
        task.expirationHandler = { sweep.cancel() }
        Task { @MainActor in
            await sweep.value
            scheduleNext()
            task.setTaskCompleted(success: !sweep.isCancelled)
        }
    }

    /// Runs one sweep over enabled participants under the time budget.
    /// Also callable from the Settings "Sync now" debug action.
    func runSweep(trigger: String) async {
        guard !isSweeping else {
            logger.logVerbose("sync", "Sweep already in progress; skipping \(trigger)")
            return
        }
        isSweeping = true
        defer { isSweeping = false }
        let start = Date()
        snapshot.lastBackgroundRun = start

        guard let token = KeychainManager.getToken(), !token.isEmpty else {
            logger.logVerbose("sync", "Sweep skipped: not authenticated")
            snapshot.save()
            return
        }

        for service in participants where service.isEnabled {
            if Task.isCancelled { break }
            if Date().timeIntervalSince(start) > sweepBudget {
                logger.logMinimal("sync", "Sweep budget exceeded; stopping before \(service.sourceKey)")
                break
            }
            await service.backgroundSync()
            if let last = service.lastSyncDate {
                snapshot.sources[service.sourceKey] = last
            }
        }

        snapshot.save()
        if let latest = snapshot.sources.values.max() {
            let rel = RelativeDateTimeFormatter().localizedString(for: latest, relativeTo: Date())
            WidgetDataService.updateLastSyncDetail("synced \(rel)")
        }
        SyncReminderScheduler.shared.rearm(from: Date())
        logger.log("sync", "Sweep \(trigger) complete in \(Int(Date().timeIntervalSince(start)))s")
    }
}
