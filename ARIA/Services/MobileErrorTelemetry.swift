import Foundation

/// Privacy-safe, metadata-ONLY telemetry for backend errors the app sees
/// (card 500s, bridge outages, auth expiry, contract decode failures). Emits a
/// tiny aggregate envelope to Nexus `POST /api/telemetry/mobile-error` so a
/// backend regression is visible as a route/status/version aggregate — with no
/// private content ever leaving the device (OB-52305).
///
/// Contract:
///   - **Best-effort:** fire-and-forget on its own URLSession; every failure is
///     swallowed. It never blocks a user flow and never throws.
///   - **Cannot recursively flood:** it never reports the telemetry route's own
///     failures (it doesn't route through `APIClient`), and it is rate-limited
///     (a sliding per-minute cap + short-window dedupe by route+status+kind).
///   - **Metadata-only:** it assembles only the allowlisted aggregate fields;
///     the route is templated so raw ids never leak, and the server re-validates.
actor MobileErrorTelemetry {
    static let shared = MobileErrorTelemetry()

    enum FailureKind: String {
        case http4xx = "http_4xx"
        case http5xx = "http_5xx"
        case network
        case decode
        case auth
    }

    enum TelemetryDomain: String {
        case platform, life, chat, settings, sync, other
    }

    private let session: URLSession
    private let logger = Logger.shared

    // Rate limiting: at most `maxPerWindow` emits per `windowSeconds`, plus a
    // short dedupe so a tight retry loop reports the same failure once.
    private var recentEmits: [Date] = []
    private var lastKeyAt: [String: Date] = [:]
    private let windowSeconds: TimeInterval = 60
    private let maxPerWindow = 20
    private let dedupeSeconds: TimeInterval = 10

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    /// Record a backend failure best-effort. Derives the route template + domain
    /// from `path`; `status` is nil for network/decode failures.
    func record(path: String, status: Int?, failureKind: FailureKind, errorCode: String? = nil) async {
        // Never report the telemetry endpoint's own failures — no recursion.
        guard !path.hasPrefix("/api/telemetry/") else { return }

        let route = Self.routeTemplate(forPath: path)
        let key = "\(route)|\(status ?? -1)|\(failureKind.rawValue)"
        let now = Date()

        // Dedupe identical failures within the short window.
        if let last = lastKeyAt[key], now.timeIntervalSince(last) < dedupeSeconds { return }
        // Sliding per-minute cap.
        recentEmits = recentEmits.filter { now.timeIntervalSince($0) < windowSeconds }
        guard recentEmits.count < maxPerWindow else { return }
        recentEmits.append(now)
        lastKeyAt[key] = now

        await post(envelope: envelope(route: route, status: status, failureKind: failureKind, domain: Self.domain(forPath: path), errorCode: errorCode))
    }

    // MARK: - Envelope (metadata-only)

    private func envelope(route: String, status: Int?, failureKind: FailureKind, domain: TelemetryDomain, errorCode: String?) -> [String: Any] {
        var body: [String: Any] = [
            "route": route,
            "failure_kind": failureKind.rawValue,
            "domain": domain.rawValue,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "os_version": Self.osVersion,
        ]
        if let status { body["status"] = status }
        if let errorCode, !errorCode.isEmpty { body["error_code"] = String(errorCode.prefix(64)) }
        return body
    }

    private func post(envelope: [String: Any]) async {
        guard let base = KeychainManager.getServerURL(), !base.isEmpty,
              let url = URL(string: base + "/api/telemetry/mobile-error"),
              let payload = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainManager.getToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = payload
        // Best-effort: swallow everything; a telemetry failure must never surface
        // or retry (that is the recursive-flood guard).
        _ = try? await session.data(for: req)
        logger.logDebug("telemetry", "mobile-error emitted:", envelope["route"] ?? "?", envelope["status"] ?? "-")
    }

    // MARK: - Derivation (pure, testable)

    private static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    /// Coarse domain from a request path (query-aware for card routes, whose
    /// Life|Platform split is a query param).
    static func domain(forPath path: String) -> TelemetryDomain {
        let p = path.split(separator: "?").first.map(String.init) ?? path
        if p.hasPrefix("/v1/chat") || p.hasPrefix("/api/chat") { return .chat }
        if p.hasPrefix("/api/cards") || p.hasPrefix("/api/card-photo") {
            if path.contains("domain=life") { return .life }
            return .platform
        }
        if p.hasPrefix("/api/health") || p.hasPrefix("/api/device-") || p.hasPrefix("/api/music") { return .sync }
        if p.hasPrefix("/api/settings") || p.hasPrefix("/api/notifications") || p.hasPrefix("/api/proactive") { return .settings }
        return .other
    }

    /// Turn a concrete request path into a route TEMPLATE so raw ids never leak
    /// into telemetry: strip the query, and replace any id-looking path segment
    /// (contains a digit, or is a UUID) with `:id`. Static route words that only
    /// contain letters/hyphens (e.g. `device-token`, `read-all`) are preserved.
    static func routeTemplate(forPath path: String) -> String {
        let raw = path.split(separator: "?").first.map(String.init) ?? path
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let templated: [String] = parts.map { seg in
            guard !seg.isEmpty else { return seg }
            if seg.contains(where: { $0.isNumber }) || isUUID(seg) { return ":id" }
            return seg
        }
        return String(templated.joined(separator: "/").prefix(120))
    }

    private static func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }

    #if DEBUG
    /// Launch-time characterization (no XCTest target in this repo). Pins the
    /// route-template redaction + domain derivation so a regression traps.
    static func runSelfCheck() {
        assert(routeTemplate(forPath: "/api/cards/abc-123/decide") == "/api/cards/:id/decide")
        assert(routeTemplate(forPath: "/api/cards/9F2A/status?kind=x") == "/api/cards/:id/status")
        assert(routeTemplate(forPath: "/api/notifications/device-token") == "/api/notifications/device-token")
        assert(routeTemplate(forPath: "/api/inbox/read-all") == "/api/inbox/read-all")
        assert(domain(forPath: "/api/cards?domain=life") == .life)
        assert(domain(forPath: "/api/cards?domain=platform") == .platform)
        assert(domain(forPath: "/v1/chat/aria") == .chat)
        assert(domain(forPath: "/api/device-activity") == .sync)
        assert(domain(forPath: "/api/notifications/device-token") == .settings)
    }
    #endif
}
