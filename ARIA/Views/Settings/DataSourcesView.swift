import SwiftUI

/// One screen for the four device pipelines: status dot, last synced, Nexus-side status, and
/// per-row Connect/Disconnect, plus one Sync Now. Replaces the four per-source screens + Sync Freshness.
struct DataSourcesView: View {
    @Environment(HealthKitService.self) private var health
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    @Environment(MusicKitService.self) private var music
    @Environment(FreshnessStore.self) private var freshness
    @Environment(DeepLinkManager.self) private var deepLink
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var reminder = SyncReminderScheduler.shared
    @State private var events = DeviceEventSync.shared
    @State private var healthFiles = HealthFilesSync.shared
    @State private var syncing = false

    var body: some View {
        List {
            Section("Sources") {
                row(DeviceSource.health, enabled: health.isEnabled, syncing: health.isSyncing, last: health.lastSyncDate, error: health.syncError,
                    connect: { await health.requestAuthorization() }, disconnect: { health.disconnect() })
                row(DeviceSource.healthFiles, enabled: healthFiles.isEnabled, syncing: healthFiles.isSyncing, last: healthFiles.lastSyncDate, error: healthFiles.syncError,
                    connect: { await healthFiles.requestAuthorization() }, disconnect: { healthFiles.disconnect() })
                row(DeviceSource.location, enabled: location.isEnabled, syncing: location.isSyncing, last: location.lastSyncDate, error: location.syncError,
                    connect: { location.requestAuthorization() }, disconnect: { location.disconnect() })
                row(DeviceSource.motion, enabled: motion.isEnabled, syncing: motion.isSyncing, last: motion.lastSyncDate, error: motion.syncError,
                    connect: { motion.enable() }, disconnect: { motion.disconnect() })
                row(DeviceSource.music, enabled: music.isEnabled, syncing: music.isSyncing, last: music.lastSyncDate, error: music.syncError,
                    connect: { await music.requestAuthorization() }, disconnect: { music.disconnect() })
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                LabeledContent("Queued") { Text("\(events.pendingCount)").foregroundStyle(ARIATheme.textSecondary) }
                if events.deadLetterCount > 0 {
                    LabeledContent("Rejected") { Text("\(events.deadLetterCount)").foregroundStyle(ARIATheme.error) }
                }
                if let err = events.lastError {
                    Text(err).font(.caption).foregroundStyle(ARIATheme.error).lineLimit(2)
                }
                if events.stats.isEmpty {
                    Text("No automation has sent anything yet. Set one up in Shortcuts → Automation (recipes: docs/automation-recipes.md).")
                        .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
                NavigationLink { AutomationSetupView() } label: { Label("Setup & test automations", systemImage: "wand.and.stars").foregroundStyle(ARIATheme.textPrimary) }
                ForEach(events.stats) { stat in
                    HStack(spacing: 12) {
                        Circle().fill(stat.quiet ? ARIATheme.accentGold : ARIATheme.success).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.automation).foregroundStyle(ARIATheme.textPrimary)
                            Text(automationSubtitle(stat)).font(.caption).foregroundStyle(ARIATheme.textSecondary).lineLimit(1)
                        }
                    }
                }
            } header: {
                Text("Automations")
            }
            .listRowBackground(ARIATheme.surface)

            Section("Nexus") {
                LabeledContent("Overall") { Text(freshness.freshness.summary.overall).foregroundStyle(ARIATheme.textSecondary) }
                LabeledContent("Last checked") { Text(freshness.lastFetchAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—").foregroundStyle(ARIATheme.textSecondary) }
                LabeledContent("Last background run") { Text(coordinator.snapshot.lastBackgroundRun.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "never").foregroundStyle(ARIATheme.textSecondary) }
                Button {
                    deepLink.pendingTab = "estate"
                    dismiss()
                } label: {
                    Label("Estate", systemImage: "building.2").foregroundStyle(ARIATheme.textPrimary)
                }
                NavigationLink { HealthFilesDetailView() } label: { Label("Last health-records sync, in detail", systemImage: "list.clipboard").foregroundStyle(ARIATheme.textPrimary) }
                Toggle("Keep Factotum synced", isOn: $reminder.isEnabled)
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                Button {
                    syncing = true
                    Task { await coordinator.runSweep(trigger: "settings"); await freshness.refresh(); await events.refreshSnapshot(); syncing = false }
                } label: { HStack { Text(syncing ? "Syncing…" : "Sync Now"); if syncing { Spacer(); ProgressView() } } }
                .disabled(syncing)
            }
            .listRowBackground(ARIATheme.surface)
        }
        .scrollContentBackground(.hidden).background(ARIATheme.background)
        .navigationTitle("Data Sources")
        .task {
            freshness.refreshIfNeeded()
            await events.refreshSnapshot()
        }
    }

    @ViewBuilder
    private func row(_ source: DeviceSource, enabled: Bool, syncing: Bool, last: Date?, error: String?,
                     connect: @escaping () async -> Void, disconnect: @escaping () -> Void) -> some View {
        let nexus = freshness.freshness.sources.first { $0.sourceKey == source.nexusRegistryKey }
        HStack(spacing: 12) {
            Circle().fill(dot(enabled: enabled, error: error, nexusStatus: nexus?.status)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Label(source.label, systemImage: source.icon).foregroundStyle(ARIATheme.textPrimary)
                Text(subtitle(enabled: enabled, syncing: syncing, last: last, error: error, nexusStatus: nexus?.status))
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                    // An error wraps (and can be copied) so its diagnostic detail isn't truncated.
                    .lineLimit(error == nil ? 1 : nil).textSelection(.enabled)
            }
            Spacer()
            if enabled {
                Button("Disconnect", role: .destructive, action: disconnect).font(.caption).buttonStyle(.bordered)
            } else {
                Button("Connect") { Task { await connect() } }.font(.caption).buttonStyle(.borderedProminent).tint(ARIATheme.accent)
            }
        }
    }

    private func dot(enabled: Bool, error: String?, nexusStatus: String?) -> Color {
        if !enabled { return ARIATheme.textMuted }
        if error != nil || nexusStatus == "error" { return ARIATheme.error }
        if nexusStatus == "stale" { return ARIATheme.accentGold }
        return ARIATheme.success
    }

    private func automationSubtitle(_ stat: DeviceEventQueueState.AutomationStat) -> String {
        let last = stat.lastAt.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "never"
        let quiet = stat.quiet ? " · gone quiet" : ""
        return "\(stat.channel.rawValue) · \(stat.count24h) in 24h · last \(last)\(quiet)"
    }

    private func subtitle(enabled: Bool, syncing: Bool, last: Date?, error: String?, nexusStatus: String?) -> String {
        if !enabled { return "Not connected" }
        if syncing { return "Syncing…" }
        if let error { return error }
        let local = last.map { "synced \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()))" } ?? "never synced"
        return nexusStatus.map { "\(local) · Nexus: \($0)" } ?? local
    }
}
