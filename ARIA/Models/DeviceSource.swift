import Foundation

/// The single canonical registry of ARIA device sources (OB-52233) — the
/// authoritative mapping between the app's local sync keys and Nexus's
/// server-side `data_source_registry.source_key`, plus the Settings label, the
/// sync API route, and the persisted enabled-flag. It exists because the two
/// truths diverged: the app's freshness keys are short (`health`/`motion`/
/// `music`) while Nexus keys are long (`healthkit`/`device_motion_activity`/
/// `device_music`/`device_location`), so a source could look connected in one
/// and stale in the other with no way to line them up. Every UI row and every
/// trace now resolves through this type. The full contract (thresholds, status
/// meanings, the offline-doesn't-clear-enables invariant) is in
/// `docs/sync-freshness-contract.md`.
struct DeviceSource: Identifiable, Sendable {
    /// The local key — `BackgroundSyncable.sourceKey` and the `SyncFreshness.sources`
    /// dictionary key. NOT renamed to the Nexus key: it is persisted in the app-group
    /// snapshot, so renaming would strand existing installs' freshness history.
    let appKey: String
    /// The server-side `data_source_registry.source_key` this source advances.
    let nexusRegistryKey: String
    let label: String
    let icon: String
    /// The Nexus route whose success advances `nexusRegistryKey`'s registry row.
    let apiRoute: String
    /// The `UserDefaults` `*_enabled` flag. Cleared only on explicit sign-out —
    /// never on a transient auth/network failure (the 2026-07-03 cascade fix).
    let enabledFlag: String

    var id: String { appKey }

    static let health = DeviceSource(appKey: "health", nexusRegistryKey: "healthkit", label: "Health", icon: "heart.fill", apiRoute: "/api/health-data", enabledFlag: "healthkit_enabled")
    static let motion = DeviceSource(appKey: "motion", nexusRegistryKey: "device_motion_activity", label: "Motion & Activity", icon: "figure.walk.motion", apiRoute: "/api/device-activity", enabledFlag: "motion_enabled")
    static let music = DeviceSource(appKey: "music", nexusRegistryKey: "device_music", label: "Music", icon: "music.note", apiRoute: "/api/device-music", enabledFlag: "music_enabled")
    /// Location self-monitors (CLVisit + significant-change OS wake) instead of
    /// joining the SyncCoordinator sweep, so it has no freshness-sweep row — but
    /// its registry mapping is canonical here for tracing.
    static let location = DeviceSource(appKey: "location", nexusRegistryKey: "device_location", label: "Location", icon: "location.fill", apiRoute: "/api/device-location", enabledFlag: "location_enabled")
    /// Shortcuts-automation events (App Intents → queue → /api/device-events). Not a
    /// freshness-UI row: its health is shown per automation in Data Sources.
    static let deviceEvents = DeviceSource(appKey: "device_events", nexusRegistryKey: "device_events", label: "Automations", icon: "bolt.horizontal.circle", apiRoute: "/api/device-events", enabledFlag: "device_events_enabled")
    /// Live HealthKit clinical records, ECGs and workout routes (/api/health-files).
    static let healthFiles = DeviceSource(appKey: "health_files", nexusRegistryKey: "healthkit_clinical", label: "Health Records & ECG", icon: "cross.case.fill", apiRoute: "/api/health-files", enabledFlag: "health_files_enabled")

    /// The sources shown in the Sync Freshness UI (the SyncCoordinator sweep
    /// participants that report a `lastSyncDate`).
    static let freshnessSweepSources: [DeviceSource] = [.health, .motion, .music]
    /// All canonical device sources (for tracing / mapping).
    static let all: [DeviceSource] = [.health, .motion, .music, .location, .deviceEvents, .healthFiles]

    /// Local app key → canonical Nexus `data_source_registry.source_key`.
    static func nexusRegistryKey(forAppKey appKey: String) -> String? {
        all.first { $0.appKey == appKey }?.nexusRegistryKey
    }

    #if DEBUG
    /// Pins the mapping so the app freshness keys and the Nexus registry keys can
    /// never silently drift apart. Wired in `AppDelegate` (`#if DEBUG`).
    static func runSelfCheck() {
        // Must match BackgroundSyncable.sourceKey + SyncFreshness.sources keys.
        assert(freshnessSweepSources.map(\.appKey) == ["health", "motion", "music"])
        assert(nexusRegistryKey(forAppKey: "health") == "healthkit")
        assert(nexusRegistryKey(forAppKey: "motion") == "device_motion_activity")
        assert(nexusRegistryKey(forAppKey: "music") == "device_music")
        assert(nexusRegistryKey(forAppKey: "location") == "device_location")
        assert(nexusRegistryKey(forAppKey: "device_events") == "device_events")
        assert(nexusRegistryKey(forAppKey: "health_files") == "healthkit_clinical")
        assert(nexusRegistryKey(forAppKey: "unmapped") == nil)
    }
    #endif
}
