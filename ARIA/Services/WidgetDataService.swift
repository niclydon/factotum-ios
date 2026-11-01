import Foundation
import WidgetKit

/// Writes lightweight data snapshots to the App Group shared container
/// so widgets can display current ARIA state without network access.
enum WidgetDataService {

    static let suiteName = "group.com.example.factotum"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Write (called from main app after syncs)

    /// Publish the One Big Thing glance (Factotum 4.0 W6) for the
    /// Control Center control and widgets.
    static func updateOneBigThing(readiness: Int?, stressIndex: Int?, forDate: String) {
        var data: [String: Any] = [
            "date": forDate,
            "updated_at": Date().timeIntervalSince1970,
        ]
        if let readiness { data["readiness"] = readiness }
        if let stressIndex { data["stress"] = stressIndex }
        sharedDefaults?.set(data, forKey: "widget_one_big_thing")
        reloadWidgets()
    }

    /// Publish Lens status (Factotum 4.0 W6) for the Control Center
    /// control: analyzed count and pending-upload count.
    static func updateLensStatus(analyzed: Int, pending: Int, lastRun: Date?) {
        var data: [String: Any] = [
            "analyzed": analyzed,
            "pending": pending,
            "updated_at": Date().timeIntervalSince1970,
        ]
        if let lastRun { data["last_run"] = lastRun.timeIntervalSince1970 }
        sharedDefaults?.set(data, forKey: "widget_lens_status")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Update the next calendar event for the widget.
    static func updateNextEvent(title: String, startDate: Date, endDate: Date, location: String?, calendarName: String?) {
        let data: [String: Any] = [
            "title": title,
            "start_date": startDate.timeIntervalSince1970,
            "end_date": endDate.timeIntervalSince1970,
            "location": location ?? "",
            "calendar_name": calendarName ?? "",
            "updated_at": Date().timeIntervalSince1970,
        ]
        sharedDefaults?.set(data, forKey: "widget_next_event")
        reloadWidgets()
    }

    /// Update today's health summary for the widget.
    static func updateHealthSummary(steps: Int?, sleepHours: Double?, heartRate: Int?, activeCalories: Int?, distance: Double?) {
        var data: [String: Any] = [
            "updated_at": Date().timeIntervalSince1970,
        ]
        if let steps { data["steps"] = steps }
        if let sleepHours { data["sleep_hours"] = sleepHours }
        if let heartRate { data["heart_rate"] = heartRate }
        if let activeCalories { data["active_calories"] = activeCalories }
        if let distance { data["distance"] = distance }
        sharedDefaults?.set(data, forKey: "widget_health")
        reloadWidgets()
    }

    /// Update the current activity/location status for the widget.
    static func updateActivityStatus(activity: String, location: String?) {
        let data: [String: Any] = [
            "activity": activity,
            "location": location ?? "",
            "updated_at": Date().timeIntervalSince1970,
        ]
        sharedDefaults?.set(data, forKey: "widget_activity")
        reloadWidgets()
    }

    // MARK: - Sync freshness (Factotum 3.2)

    static func updateFreshnessOverall(_ overall: String) {
        sharedDefaults?.set(overall, forKey: "widget_freshness_overall")
        reloadWidgets()
    }

    static func updateLastSyncDetail(_ detail: String) {
        sharedDefaults?.set(detail, forKey: "widget_last_sync_detail")
        reloadWidgets()
    }

    static func updateUpdateAvailable(_ available: Bool) {
        sharedDefaults?.set(available, forKey: "widget_update_available")
        reloadWidgets()
    }

    struct Freshness {
        let overall: String?
        let lastSyncDetail: String?
        let updateAvailable: Bool
    }

    static func readFreshness() -> Freshness {
        Freshness(
            overall: sharedDefaults?.string(forKey: "widget_freshness_overall"),
            lastSyncDetail: sharedDefaults?.string(forKey: "widget_last_sync_detail"),
            updateAvailable: sharedDefaults?.bool(forKey: "widget_update_available") ?? false
        )
    }

    /// Clear all widget data (on logout).
    static func clearAll() {
        let keys = ["widget_next_event", "widget_health", "widget_activity",
                    "widget_freshness_overall", "widget_last_sync_detail", "widget_update_available"]
        for key in keys {
            sharedDefaults?.removeObject(forKey: key)
        }
        reloadWidgets()
    }

    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Read (called from widget extension)

    struct NextEvent {
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String
        let calendarName: String
        let updatedAt: Date
    }

    static func readNextEvent() -> NextEvent? {
        guard let data = sharedDefaults?.dictionary(forKey: "widget_next_event"),
              let title = data["title"] as? String,
              let startTS = data["start_date"] as? TimeInterval,
              let endTS = data["end_date"] as? TimeInterval else { return nil }
        return NextEvent(
            title: title,
            startDate: Date(timeIntervalSince1970: startTS),
            endDate: Date(timeIntervalSince1970: endTS),
            location: data["location"] as? String ?? "",
            calendarName: data["calendar_name"] as? String ?? "",
            updatedAt: Date(timeIntervalSince1970: data["updated_at"] as? TimeInterval ?? 0)
        )
    }

    struct HealthSummary {
        let steps: Int?
        let sleepHours: Double?
        let heartRate: Int?
        let activeCalories: Int?
        let distance: Double?
        let updatedAt: Date
    }

    static func readHealthSummary() -> HealthSummary? {
        guard let data = sharedDefaults?.dictionary(forKey: "widget_health") else { return nil }
        return HealthSummary(
            steps: data["steps"] as? Int,
            sleepHours: data["sleep_hours"] as? Double,
            heartRate: data["heart_rate"] as? Int,
            activeCalories: data["active_calories"] as? Int,
            distance: data["distance"] as? Double,
            updatedAt: Date(timeIntervalSince1970: data["updated_at"] as? TimeInterval ?? 0)
        )
    }

    struct ActivityStatus {
        let activity: String
        let location: String
        let updatedAt: Date
    }

    static func readActivityStatus() -> ActivityStatus? {
        guard let data = sharedDefaults?.dictionary(forKey: "widget_activity"),
              let activity = data["activity"] as? String else { return nil }
        return ActivityStatus(
            activity: activity,
            location: data["location"] as? String ?? "",
            updatedAt: Date(timeIntervalSince1970: data["updated_at"] as? TimeInterval ?? 0)
        )
    }
}
