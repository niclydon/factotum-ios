import Foundation

/// Update awareness for the Ad Hoc lane. Two signals, either can speak:
/// 1. The OTA manifest on the OTA host (AppConfig) — the newest Ad Hoc
///    build's marketing version, served by the same page installs use.
/// 2. The bootstrap contract's `app_version` hints (OB-52301) — Nexus can
///    recommend or require a version. These were decoded but never
///    consumed before 3.2.0; this checker is the consumer.
/// `required` (below the server minimum) wins over `available`.
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case unknown
        case checking
        case upToDate
        case available(String)
        case required(String)
        case failed
    }

    private(set) var state: State = .unknown
    private(set) var lastCheckedAt: Date?
    /// The version on offer when state is .available / .required.
    private(set) var availableVersion: String?
    /// Release notes for the offered version, when the OTA page published
    /// them (release-notes.json beside the manifest) for this exact
    /// version. Nil when the file is absent or describes another version.
    private(set) var availableReleaseNotes: String?

    private let lastCheckKey = "factotum_update_last_check"
    private let logger = Logger.shared

    private init() {
        lastCheckedAt = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    /// Automatic checks throttle to twice a day; the manifest only changes
    /// when a new Ad Hoc build is staged.
    func refreshIfNeeded() {
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < 12 * 3600 { return }
        Task { await refresh(manual: false) }
    }

    func refresh(manual: Bool) async {
        if case .checking = state { return }
        state = .checking
        let current = AppConfig.appVersion

        var manifestVersion: String?
        if let (data, response) = try? await URLSession.shared.data(from: AppConfig.otaManifestURL),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let items = plist["items"] as? [[String: Any]],
           let metadata = items.first?["metadata"] as? [String: Any] {
            manifestVersion = metadata["bundle-version"] as? String
        }

        let hints = BootstrapStore.shared.bootstrap.appVersion
        let sawServer = manifestVersion != nil || BootstrapStore.shared.hasServerSnapshot

        if let minimum = hints.minimum, AppConfig.isVersion(minimum, newerThan: current) {
            state = .required(minimum)
        } else if let mv = manifestVersion, AppConfig.isVersion(mv, newerThan: current) {
            state = .available(mv)
        } else if let recommended = hints.recommended, AppConfig.isVersion(recommended, newerThan: current) {
            state = .available(recommended)
        } else if sawServer {
            state = .upToDate
        } else {
            // Nothing reachable (off LAN/tailnet and bootstrap never
            // fetched). An automatic check stays silent; a manual one
            // is allowed to say so.
            state = manual ? .failed : .unknown
        }

        // Release notes for the offered version (3.4.0): the cut publishes
        // release-notes.json next to the manifest. Only surface notes whose
        // version matches the version actually on offer.
        switch state {
        case .available(let v), .required(let v):
            availableVersion = v
            availableReleaseNotes = await fetchReleaseNotes(for: v)
        default:
            availableVersion = nil
            availableReleaseNotes = nil
        }

        if sawServer {
            lastCheckedAt = Date()
            UserDefaults.standard.set(lastCheckedAt, forKey: lastCheckKey)
        }
        WidgetDataService.updateUpdateAvailable(isUpdateAvailable)
        logger.log("update", "check complete: state=\(state)")
    }

    var isUpdateAvailable: Bool {
        switch state {
        case .available, .required: return true
        default: return false
        }
    }

    private func fetchReleaseNotes(for version: String) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: AppConfig.otaReleaseNotesURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] as? String == version,
              let notes = json["notes"] as? String, !notes.isEmpty
        else { return nil }
        return notes
    }
}
