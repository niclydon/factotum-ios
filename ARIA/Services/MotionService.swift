import Foundation
import CoreMotion

/// Bridges iOS Motion & Activity data to the ARIA server.
///
/// Uses CMMotionActivityManager to detect the user's current activity
/// (stationary, walking, running, cycling, driving). Runs on the M-series
/// coprocessor with negligible battery impact.
///
/// Also supports a 7-day historical backfill that queries CoreMotion's
/// on-device activity history, groups by hour, and bulk-syncs to the server.
@Observable
@MainActor
final class MotionService {

    static let shared = MotionService()

    private let logger = Logger.shared

    // MARK: - State

    var isAvailable = false
    var isSyncing = false
    var syncError: String?
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "motion_last_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "motion_last_sync") }
    }
    var currentActivity: String?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "motion_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "motion_enabled") }
    }

    /// Whether a backfill has been completed since last enable.
    var hasBackfilled: Bool {
        get { UserDefaults.standard.bool(forKey: "motion_backfilled") }
        set { UserDefaults.standard.set(newValue, forKey: "motion_backfilled") }
    }

    // MARK: - Private

    private let activityManager = CMMotionActivityManager()

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Availability

    func checkAvailability() {
        let available = CMMotionActivityManager.isActivityAvailable()
        isAvailable = available
        // Only clear the persisted enable when motion is EXPLICITLY denied or
        // restricted. `isActivityAvailable()` can briefly report false on a
        // cold launch (after overnight app eviction the coprocessor/auth state
        // hasn't re-resolved yet); that transient blip must NOT wipe
        // `motion_enabled`. A genuine denial/restriction is durable and will
        // surface as a denied/restricted authorization status.
        if isEnabled {
            let status = CMMotionActivityManager.authorizationStatus()
            if status == .denied || status == .restricted {
                isEnabled = false
            }
        }
    }

    func enable() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            syncError = "Motion activity is not available on this device."
            return
        }
        isAvailable = true
        isEnabled = true
        syncError = nil
    }

    func disconnect() {
        isEnabled = false
        isAvailable = false
        lastSyncDate = nil
        currentActivity = nil
        syncError = nil
        hasBackfilled = false
    }

    // MARK: - Sync

    func sync() async {
        guard !isSyncing, isEnabled, isAvailable else { return }
        isSyncing = true
        syncError = nil

        defer { isSyncing = false }

        do {
            // Run backfill on first sync or after re-enable
            if !hasBackfilled {
                await backfillActivities()
            }

            guard let activity = await queryCurrentActivity() else {
                return
            }

            let record = ActivityRecord(
                timestamp: Self.iso8601Formatter.string(from: Date()),
                stationary: activity.stationary,
                walking: activity.walking,
                running: activity.running,
                cycling: activity.cycling,
                automotive: activity.automotive,
                confidence: describeConfidence(activity.confidence)
            )

            currentActivity = activity.description

            let response = try await APIClient.shared.syncActivity(activity: record)
            if response.saved {
                lastSyncDate = Date()
                // Update widget
                WidgetDataService.updateActivityStatus(activity: activity.description, location: nil)
            }
        } catch {
            logger.logMinimal("motion", "Sync failed:", error.localizedDescription)
            syncError = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - 7-Day Backfill

    /// Queries the last 7 days of CoreMotion activity history, groups by hour,
    /// picks the dominant activity per hour, and bulk-syncs to the server.
    func backfillActivities() async {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)

        logger.log("motion", "Starting 7-day activity backfill from \(Self.iso8601Formatter.string(from: sevenDaysAgo))")

        do {
            let activities = try await queryActivities(from: sevenDaysAgo, to: now)
            guard !activities.isEmpty else {
                logger.logVerbose("motion", "Backfill: no activities found in 7-day window")
                hasBackfilled = true
                return
            }

            logger.logVerbose("motion", "Backfill: queried \(activities.count) raw activity records")

            // Group by hour and pick dominant activity per hour
            let hourlyRecords = groupByHour(activities: activities)
            guard !hourlyRecords.isEmpty else {
                logger.logVerbose("motion", "Backfill: no valid hourly records after grouping")
                hasBackfilled = true
                return
            }

            logger.logVerbose("motion", "Backfill: grouped into \(hourlyRecords.count) hourly records, syncing...")

            let response = try await APIClient.shared.syncActivities(activities: hourlyRecords)
            logger.log("motion", "Backfill complete: saved \(response.saved) of \(response.total) records (\(response.valid) valid)")
            hasBackfilled = true
        } catch {
            logger.logMinimal("motion", "Backfill failed:", error.localizedDescription)
            // Don't block future syncs -- backfill will retry next sync cycle
        }
    }

    /// Queries CoreMotion for all activities in the given range.
    private func queryActivities(from start: Date, to end: Date) async throws -> [ActivityState] {
        try await withCheckedThrowingContinuation { continuation in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let states: [ActivityState] = (activities ?? []).compactMap { activity in
                    // Skip unknown activity states
                    guard activity.automotive || activity.cycling || activity.running
                            || activity.walking || activity.stationary else {
                        return nil
                    }

                    let desc = activity.automotive ? "Driving"
                        : activity.cycling ? "Cycling"
                        : activity.running ? "Running"
                        : activity.walking ? "Walking"
                        : "Stationary"

                    return ActivityState(
                        startDate: activity.startDate,
                        stationary: activity.stationary,
                        walking: activity.walking,
                        running: activity.running,
                        cycling: activity.cycling,
                        automotive: activity.automotive,
                        confidence: activity.confidence,
                        description: desc
                    )
                }
                continuation.resume(returning: states)
            }
        }
    }

    /// Groups activity records by calendar hour, picking the dominant (most frequent)
    /// activity state for each hour.
    private func groupByHour(activities: [ActivityState]) -> [ActivityRecord] {
        let calendar = Calendar.current

        // Group by hour
        var hourBuckets: [DateComponents: [ActivityState]] = [:]
        for activity in activities {
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: activity.startDate)
            hourBuckets[components, default: []].append(activity)
        }

        // For each hour, pick the dominant activity
        var records: [ActivityRecord] = []
        for (components, bucket) in hourBuckets {
            guard let hourDate = calendar.date(from: components) else { continue }
            guard let dominant = dominantActivity(in: bucket) else { continue }

            records.append(ActivityRecord(
                timestamp: Self.iso8601Formatter.string(from: hourDate),
                stationary: dominant.stationary,
                walking: dominant.walking,
                running: dominant.running,
                cycling: dominant.cycling,
                automotive: dominant.automotive,
                confidence: describeConfidence(dominant.confidence)
            ))
        }

        // Sort chronologically
        return records.sorted { $0.timestamp < $1.timestamp }
    }

    /// Finds the most common activity type in a bucket of activities.
    private func dominantActivity(in activities: [ActivityState]) -> ActivityState? {
        guard !activities.isEmpty else { return nil }

        // Count by activity type description
        var counts: [String: Int] = [:]
        for a in activities {
            counts[a.description, default: 0] += 1
        }

        // Find the type with the highest count
        guard let dominantType = counts.max(by: { $0.value < $1.value })?.key else {
            return activities.last
        }

        // Return the last activity of that type (most recent, likely highest confidence)
        return activities.last { $0.description == dominantType } ?? activities.last
    }

    // MARK: - Core Motion Queries

    /// Parsed activity state (Sendable-safe).
    struct ActivityState: Sendable {
        let startDate: Date
        let stationary: Bool
        let walking: Bool
        let running: Bool
        let cycling: Bool
        let automotive: Bool
        let confidence: CMMotionActivityConfidence
        let description: String
    }

    private func queryCurrentActivity() async -> ActivityState? {
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-300)

        return await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: fiveMinutesAgo, to: now, to: .main) { activities, error in
                if let error {
                    print("[MotionService] Query error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let activity = activities?.last else {
                    continuation.resume(returning: nil)
                    return
                }

                // Skip unknown activity states -- none of the booleans are true
                guard activity.automotive || activity.cycling || activity.running
                        || activity.walking || activity.stationary else {
                    continuation.resume(returning: nil)
                    return
                }

                let desc = activity.automotive ? "Driving"
                    : activity.cycling ? "Cycling"
                    : activity.running ? "Running"
                    : activity.walking ? "Walking"
                    : "Stationary"

                let state = ActivityState(
                    startDate: activity.startDate,
                    stationary: activity.stationary,
                    walking: activity.walking,
                    running: activity.running,
                    cycling: activity.cycling,
                    automotive: activity.automotive,
                    confidence: activity.confidence,
                    description: desc
                )
                continuation.resume(returning: state)
            }
        }
    }

    private func describeConfidence(_ confidence: CMMotionActivityConfidence) -> String {
        switch confidence {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        @unknown default: return "unknown"
        }
    }
}
