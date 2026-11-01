import Foundation
import UIKit

/// Factotum Phase 2 device citizenship, app half: this phone introduces
/// itself to Nexus as a managed device (POST /api/device-registration),
/// the same way the Macs register in the `factotum_*` tables.
///
/// Until the Nexus endpoint ships, a 404 is a first-class state
/// (`pendingEndpoint`), not an error: registration retries quietly on the
/// next launch / foreground and the This Device screen shows the truth.
/// Registration is idempotent server-side (upsert by device_id); the
/// client only re-sends when the payload actually changes.
struct DeviceRegistrationPayload: Codable, Sendable {
    let deviceId: String
    let deviceName: String
    let model: String
    let osVersion: String
    let appVersion: String
    let appBuild: String
    let bundleId: String
    let distribution: String
    let pushToken: String?
    let profileExpiresAt: String?
    let lensMetadataPending: Int?
    let lensLastEnrichmentAt: String?
    let registeredAt: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case model
        case osVersion = "os_version"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case bundleId = "bundle_id"
        case distribution
        case pushToken = "push_token"
        case profileExpiresAt = "profile_expires_at"
        case lensMetadataPending = "lens_metadata_pending"
        case lensLastEnrichmentAt = "lens_last_enrichment_at"
        case registeredAt = "registered_at"
    }

    /// Change-detection fingerprint: everything except the timestamp.
    var fingerprint: String {
        [deviceId, deviceName, model, osVersion, appVersion, appBuild,
         bundleId, distribution, pushToken ?? "-", profileExpiresAt ?? "-",
         lensMetadataPending.map(String.init) ?? "-", lensLastEnrichmentAt ?? "-"]
            .joined(separator: "|")
    }
}

@Observable
@MainActor
final class DeviceRegistrationService {
    static let shared = DeviceRegistrationService()

    enum State: Equatable {
        case unknown
        case registered(Date)
        case pendingEndpoint
        case failed(String)
    }

    private(set) var state: State = .unknown
    private(set) var lastRegisteredAt: Date?
    private(set) var isRegistering = false

    private let stateKey = "factotum_device_registration_v1"
    private let logger = Logger.shared

    private struct Persisted: Codable {
        var fingerprint: String
        var registeredAt: Date
    }

    private init() {
        if let persisted = loadPersisted() {
            lastRegisteredAt = persisted.registeredAt
            state = .registered(persisted.registeredAt)
        }
    }

    // MARK: - Device facts

    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return Mirror(reflecting: info.machine).children.reduce("") { acc, child in
            guard let value = child.value as? Int8, value != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(value)))
        }
    }

    /// Expiration of the embedded provisioning profile, if one is embedded
    /// (Ad Hoc / Development / TestFlight builds carry one; App Store
    /// builds carry a store profile with no meaningful expiry here).
    static var profileExpiration: Date? { profileInfo?.expiration }

    static var profileName: String? { profileInfo?.name }

    private static var profileInfo: (name: String?, expiration: Date?)? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // The profile is a CMS blob wrapping a plist; extract the XML.
        guard let start = data.range(of: Data("<?xml".utf8))?.lowerBound,
              let endMarker = data.range(of: Data("</plist>".utf8))?.upperBound else { return nil }
        let plistData = data[start..<endMarker]
        guard let dict = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return (dict["Name"] as? String, dict["ExpirationDate"] as? Date)
    }

    static var distribution: String {
        #if DEBUG
        return "development"
        #else
        guard let name = profileName else { return "app-store" }
        if name.localizedCaseInsensitiveContains("ad hoc") { return "adhoc" }
        if name.localizedCaseInsensitiveContains("development") { return "development" }
        if name.localizedCaseInsensitiveContains("app store") || name.localizedCaseInsensitiveContains("distribution") { return "app-store" }
        return "testflight"
        #endif
    }

    func currentPayload() -> DeviceRegistrationPayload {
        let iso = ISO8601DateFormatter()
        // Lens enrichment observability (4.1.1): LensService stamps its
        // pending count and last-run time into UserDefaults; the server
        // (OB-68450) stores both on factotum_devices so a quiet lane is
        // classifiable without a device-side look. Never stamped yet
        // means the fields are simply omitted.
        let defaults = UserDefaults.standard
        let lensPending = defaults.object(forKey: "lens.metadataPending") as? Int
        let lensLastRun = (defaults.object(forKey: "lens.lastEnrichmentRunAt") as? Date)
            .map { iso.string(from: $0) }
        return DeviceRegistrationPayload(
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            deviceName: UIDevice.current.name,
            model: Self.modelIdentifier,
            osVersion: UIDevice.current.systemVersion,
            appVersion: AppConfig.appVersion,
            appBuild: AppConfig.appBuild,
            bundleId: AppConfig.bundleID,
            distribution: Self.distribution,
            pushToken: PushNotificationService.shared.deviceToken,
            profileExpiresAt: Self.profileExpiration.map { iso.string(from: $0) },
            lensMetadataPending: lensPending,
            lensLastEnrichmentAt: lensLastRun,
            registeredAt: iso.string(from: Date())
        )
    }

    // MARK: - Registration

    /// Registers only when the payload changed since the last success
    /// (new build, new OS, new push token, new profile). Cheap to call on
    /// every launch and foreground.
    func registerIfNeeded() {
        let payload = currentPayload()
        if case .registered = state, loadPersisted()?.fingerprint == payload.fingerprint {
            return
        }
        Task { await registerNow() }
    }

    func registerNow() async {
        guard !isRegistering else { return }
        isRegistering = true
        defer { isRegistering = false }
        let payload = currentPayload()
        do {
            try await APIClient.shared.registerDevice(payload)
            let now = Date()
            lastRegisteredAt = now
            state = .registered(now)
            savePersisted(Persisted(fingerprint: payload.fingerprint, registeredAt: now))
            logger.log("device", "registered with Nexus (\(payload.appVersion)/\(payload.appBuild), \(payload.distribution))")
        } catch APIError.serverError(let code, _) where code == 404 {
            // Endpoint not deployed yet — Phase 2's Nexus half. Quiet state.
            state = .pendingEndpoint
            logger.log("device", "registration endpoint not live yet (404); will retry next launch")
        } catch APIError.unauthorized {
            state = .failed("Sign-in required")
        } catch {
            state = .failed(error.localizedDescription)
            logger.logMinimal("device", "registration failed:", error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func loadPersisted() -> Persisted? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(Persisted.self, from: data)
    }

    private func savePersisted(_ value: Persisted) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}
