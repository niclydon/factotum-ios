import Foundation

/// Holds the last successful mobile estate aggregate from Nexus (OB-66209).
/// Failures leave prior/default state in place; the cached snapshot renders
/// offline and the view labels its age. Mirrors FreshnessStore.
@Observable
@MainActor
final class EstateStore {
    static let shared = EstateStore()

    private(set) var estate: MobileEstate = .empty
    private(set) var hasServerSnapshot: Bool = false
    private(set) var lastFetchStatus: String = "not_fetched"
    private(set) var lastFetchAt: Date?
    private(set) var isFetching: Bool = false

    private let cacheKey = "mobile_estate_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(MobileEstate.self, from: data) {
            estate = cached
            hasServerSnapshot = true
            lastFetchStatus = "cached"
        }
    }

    /// Fire-and-forget refresh. Safe to call from view tasks.
    func refreshIfNeeded() {
        guard !isFetching else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let next = try await APIClient.shared.fetchMobileEstate()
            estate = next
            hasServerSnapshot = true
            lastFetchStatus = "ok"
            lastFetchAt = Date()
            if let data = try? JSONEncoder().encode(next) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            Logger.shared.log(
                "estate",
                "ok hosts=\(next.summary.hostsReporting) stale=\(next.summary.hostsStale) outdated=\(next.summary.totalOutdatedPackages) devices=\(next.devices.count)"
            )
        } catch APIError.unauthorized {
            lastFetchStatus = "unauthorized"
            Logger.shared.logMinimal("estate", "fetch unauthorized")
        } catch {
            lastFetchStatus = "failed"
            Logger.shared.logMinimal("estate", "fetch failed:", error.localizedDescription)
        }
    }

    /// This phone's server-side registration row (factotum_devices), matched
    /// by identifierForVendor — what Nexus actually holds, not local state.
    var thisDevice: MobileEstate.Device? {
        let id = DeviceRegistrationService.shared.currentPayload().deviceId
        return estate.devices.first { $0.deviceId == id }
    }

    /// Per-host detail for the drill-down view (3.4.0). Fetched on demand,
    /// not cached: the lists are long and the view is occasional.
    func hostDetail(_ host: String) async -> MobileEstateHostDetail? {
        do {
            return try await APIClient.shared.fetchEstateHostDetail(host: host)
        } catch {
            Logger.shared.logMinimal("estate", "host detail fetch failed:", error.localizedDescription)
            return nil
        }
    }
}
