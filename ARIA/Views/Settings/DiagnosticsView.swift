import SwiftUI

/// Settings → Diagnostics. One shareable snapshot of everything a
/// support session used to have to ask for by hand: device facts,
/// distribution state, registration state, per-source freshness from
/// both the phone and Nexus, background-run history, and the automation
/// queue. No tokens, no content — state only.
struct DiagnosticsView: View {
    @Environment(HealthKitService.self) private var health
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    @Environment(MusicKitService.self) private var music
    @Environment(FreshnessStore.self) private var freshness
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var events = DeviceEventSync.shared
    @State private var healthFiles = HealthFilesSync.shared
    @State private var registrar = DeviceRegistrationService.shared
    @State private var updater = UpdateChecker.shared
    @State private var bootstrap = BootstrapStore.shared

    var body: some View {
        ScrollView {
            Text(report)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(ARIATheme.background)
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: report) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }

    private func rel(_ date: Date?) -> String {
        guard let date else { return "never" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var report: String {
        var lines: [String] = []
        lines.append("Factotum diagnostics — \(Date().formatted(.iso8601))")
        lines.append("")
        lines.append("DEVICE")
        lines.append("name: \(UIDevice.current.name)")
        lines.append("model: \(DeviceRegistrationService.modelIdentifier)")
        lines.append("ios: \(UIDevice.current.systemVersion)")
        lines.append("idfv: \(UIDevice.current.identifierForVendor?.uuidString ?? "-")")
        lines.append("")
        lines.append("APP")
        lines.append("version: \(AppConfig.appVersion) (\(AppConfig.appBuild))")
        lines.append("bundle: \(AppConfig.bundleID)")
        lines.append("distribution: \(DeviceRegistrationService.distribution)")
        lines.append("profile: \(DeviceRegistrationService.profileName ?? "-")")
        lines.append("profile_expires: \(DeviceRegistrationService.profileExpiration?.formatted(.iso8601) ?? "-")")
        lines.append("update_state: \(String(describing: updater.state))")
        lines.append("registration: \(String(describing: registrar.state))")
        lines.append("last_registered: \(rel(registrar.lastRegisteredAt))")
        lines.append("push_token: \(PushNotificationService.shared.deviceToken != nil ? "present" : "absent")")
        lines.append("")
        lines.append("SOURCES (local)")
        lines.append("health: enabled=\(health.isEnabled) last=\(rel(health.lastSyncDate)) error=\(health.syncError ?? "-")")
        lines.append("health_files: enabled=\(healthFiles.isEnabled) last=\(rel(healthFiles.lastSyncDate)) error=\(healthFiles.syncError ?? "-")")
        lines.append("location: enabled=\(location.isEnabled) last=\(rel(location.lastSyncDate)) error=\(location.syncError ?? "-")")
        lines.append("motion: enabled=\(motion.isEnabled) last=\(rel(motion.lastSyncDate)) error=\(motion.syncError ?? "-")")
        lines.append("music: enabled=\(music.isEnabled) last=\(rel(music.lastSyncDate)) error=\(music.syncError ?? "-")")
        lines.append("")
        lines.append("BACKGROUND")
        lines.append("last_background_run: \(rel(coordinator.snapshot.lastBackgroundRun))")
        lines.append("")
        lines.append("AUTOMATIONS")
        lines.append("queued: \(events.pendingCount) rejected: \(events.deadLetterCount)")
        lines.append("last_error: \(events.lastError ?? "-")")
        for stat in events.stats {
            lines.append("- \(stat.automation): \(stat.count24h) in 24h, last \(rel(stat.lastAt))\(stat.quiet ? ", quiet" : "")")
        }
        lines.append("")
        lines.append("NEXUS FRESHNESS (server)")
        lines.append("overall: \(freshness.freshness.summary.overall) fresh=\(freshness.freshness.summary.fresh) stale=\(freshness.freshness.summary.stale) error=\(freshness.freshness.summary.error) empty=\(freshness.freshness.summary.empty)")
        lines.append("fetched: \(rel(freshness.lastFetchAt)) status=\(freshness.lastFetchStatus)")
        for source in freshness.freshness.sources {
            lines.append("- \(source.sourceKey): \(source.status) last_seen=\(source.lastSeenAt ?? "-")")
        }
        lines.append("")
        lines.append("BOOTSTRAP")
        lines.append("contract: \(bootstrap.bootstrap.contractVersion) fetch=\(bootstrap.lastFetchStatus)")
        lines.append("server_minimum: \(bootstrap.bootstrap.appVersion.minimum ?? "-") recommended: \(bootstrap.bootstrap.appVersion.recommended ?? "-")")
        return lines.joined(separator: "\n")
    }
}
