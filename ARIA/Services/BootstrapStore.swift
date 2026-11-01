import Foundation

/// Holds the last successful mobile bootstrap/capabilities snapshot (OB-52301).
/// Fetch is best-effort and never blocks chat/login. Failures are logged without
/// private content and leave prior/default capabilities in place for UI gating.
@Observable
@MainActor
final class BootstrapStore {
    static let shared = BootstrapStore()

    /// Last known capabilities (defaults until first success).
    private(set) var bootstrap: MobileBootstrap = .offlineDefaults
    /// True after at least one successful network fetch this process lifetime.
    private(set) var hasServerSnapshot: Bool = false
    /// Non-secret status for Settings / degraded copy.
    private(set) var lastFetchStatus: String = "not_fetched"
    private(set) var lastFetchAt: Date?
    private(set) var isFetching: Bool = false

    private let cacheKey = "mobile_bootstrap_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(MobileBootstrap.self, from: data) {
            bootstrap = cached
            hasServerSnapshot = true
            lastFetchStatus = "cached"
        }
    }

    /// Fire-and-forget refresh. Safe to call on every auth/startServices path.
    func refreshIfNeeded() {
        guard !isFetching else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let next = try await APIClient.shared.fetchMobileBootstrap()
            bootstrap = next
            hasServerSnapshot = true
            lastFetchStatus = "ok"
            lastFetchAt = Date()
            if let data = try? JSONEncoder().encode(next) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            Logger.shared.log(
                "bootstrap",
                "ok contract=\(next.contractVersion) review_cards=\(next.supportedFeatures.reviewCards)"
            )
        } catch APIError.unauthorized {
            lastFetchStatus = "unauthorized"
            Logger.shared.logMinimal("bootstrap", "fetch unauthorized")
        } catch {
            lastFetchStatus = "failed"
            // Metadata only — never log response bodies or tokens.
            Logger.shared.logMinimal("bootstrap", "fetch failed:", error.localizedDescription)
        }
    }

    // Convenience gates for Views / stores
    var reviewCardsEnabled: Bool { bootstrap.supportedFeatures.reviewCards }
    var inboxEnabled: Bool { bootstrap.supportedFeatures.inbox }
    var proactiveEnabled: Bool { bootstrap.supportedFeatures.proactive }
    var commandAskEnabled: Bool { bootstrap.supportedFeatures.commandAsk }
}
