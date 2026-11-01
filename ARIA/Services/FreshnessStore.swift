import Foundation

/// Holds the last successful mobile freshness aggregate from Nexus (OB-52302).
/// Reconciles with local `SyncFreshness` — never overwrites on-device last-run
/// timestamps. Failures leave prior/default state in place.
@Observable
@MainActor
final class FreshnessStore {
    static let shared = FreshnessStore()

    private(set) var freshness: MobileFreshness = .offlineDefaults
    private(set) var hasServerSnapshot: Bool = false
    private(set) var lastFetchStatus: String = "not_fetched"
    private(set) var lastFetchAt: Date?
    private(set) var isFetching: Bool = false

    private let cacheKey = "mobile_freshness_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(MobileFreshness.self, from: data) {
            freshness = cached
            hasServerSnapshot = true
            lastFetchStatus = "cached"
        }
    }

    /// Fire-and-forget refresh. Safe to call from Settings / launch paths.
    func refreshIfNeeded() {
        guard !isFetching else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let next = try await APIClient.shared.fetchMobileFreshness()
            freshness = next
            hasServerSnapshot = true
            lastFetchStatus = "ok"
            lastFetchAt = Date()
            if let data = try? JSONEncoder().encode(next) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            WidgetDataService.updateFreshnessOverall(next.summary.overall)
            Logger.shared.log(
                "freshness",
                "ok overall=\(next.summary.overall) fresh=\(next.summary.fresh) stale=\(next.summary.stale) error=\(next.summary.error) empty=\(next.summary.empty)"
            )
        } catch APIError.unauthorized {
            lastFetchStatus = "unauthorized"
            Logger.shared.logMinimal("freshness", "fetch unauthorized")
        } catch {
            lastFetchStatus = "failed"
            Logger.shared.logMinimal("freshness", "fetch failed:", error.localizedDescription)
        }
    }

    /// Look up a Nexus-reported source by app key (DeviceSource.appKey).
    func source(forAppKey appKey: String) -> MobileFreshness.Source? {
        freshness.sources.first { $0.appKey == appKey }
    }

    var overallStatus: String { freshness.summary.overall }
    var isDegraded: Bool {
        let o = freshness.summary.overall
        return o == "degraded" || o == "error"
    }
}
