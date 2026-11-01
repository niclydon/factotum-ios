import Foundation

/// Factotum iOS distribution + identity constants for the Ad Hoc lane
/// (primary distribution since 2026-10-17; App Store Connect is the backup).
/// One home for the OTA URLs so the update checker, Settings, and future
/// surfaces never drift apart.
enum AppConfig {
    /// OTA install page (LAN/tailnet only, house Caddy/CoreDNS pattern).
    /// The same URL serves every build; the page always points at the
    /// newest Ad Hoc IPA and manifest.
    static let otaInstallURL = URL(string: "https://factotum-ios.example.com/your-build-token/")!
    static let otaManifestURL = URL(string: "https://factotum-ios.example.com/your-build-token/manifest.plist")!
    /// Release notes for the newest staged build, written by the release
    /// cut next to the manifest; consumed by UpdateChecker so the update
    /// card can say what changed, not just that a version exists.
    static let otaReleaseNotesURL = URL(string: "https://factotum-ios.example.com/your-build-token/release-notes.json")!

    /// Base URL of the personal backend the app talks to.
    /// Override with the `FactotumBackendBaseURL` Info key;
    /// the default is an example value — set it to your
    /// own backend before building.
    static var backendBaseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "FactotumBackendBaseURL") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.example.com")!
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "?" }

    /// Dotted-numeric version compare ("3.10.0" > "3.9.9"). Non-numeric
    /// components count as 0; missing components count as 0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
