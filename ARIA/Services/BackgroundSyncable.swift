import Foundation

/// Uniform surface the SyncCoordinator iterates during a background sweep.
/// Conformers reuse their existing incremental `sync()` paths.
@MainActor
protocol BackgroundSyncable {
    /// Stable key used for freshness records and data_source_registry alignment.
    var sourceKey: String { get }
    var isEnabled: Bool { get }
    var lastSyncDate: Date? { get }
    /// Bounded, recent-window sync. Conformers handle their own errors internally
    /// (matching the existing `sync()` contract) so this is non-throwing.
    func backgroundSync() async
}

extension MotionService: BackgroundSyncable {
    var sourceKey: String { "motion" }
    func backgroundSync() async {
        checkAvailability()
        await sync()
    }
}

extension MusicKitService: BackgroundSyncable {
    var sourceKey: String { "music" }
    func backgroundSync() async {
        checkAuthorization()
        await sync()
    }
}
