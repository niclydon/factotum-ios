import Foundation

/// Persisted record of background-sync freshness, shared with widgets/extensions
/// via the app group so the Settings UI and widgets read the same state.
struct SyncFreshness: Codable, Sendable {
    /// When the last background sweep ran (regardless of per-source outcome).
    var lastBackgroundRun: Date?
    /// sourceKey ("health"/"motion"/"music") -> that source's lastSyncDate after the sweep.
    var sources: [String: Date]

    static let appGroup = "group.com.example.factotum"
    private static let storageKey = "sync_freshness_snapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> SyncFreshness {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(SyncFreshness.self, from: data) else {
            return SyncFreshness(lastBackgroundRun: nil, sources: [:])
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults.set(data, forKey: Self.storageKey)
    }
}
