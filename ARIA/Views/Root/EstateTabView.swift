import SwiftUI

/// The Estate tab (Phase 3, OB-66209). Replaces the 3.2.0 Settings stopgap:
/// Nexus freshness on top, one section per Mac from its Factotum registry
/// (factotum_* aggregates), and this iPhone's server-side registration row.
/// Aggregate-only — the phone reads Nexus, never the hosts.
struct EstateTabView: View {
    @Environment(FreshnessStore.self) private var freshness
    @Environment(EstateStore.self) private var estateStore

    var body: some View {
        List {
            nexusSection
            ForEach(estateStore.estate.hosts) { host in
                hostSection(host)
            }
            thisPhoneSection
            if !estateStore.hasServerSnapshot {
                Section {
                    Text("No estate snapshot yet — pull to refresh or reopen when Nexus is reachable.")
                        .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
                .listRowBackground(ARIATheme.glassSurface)
            }
        }
        .scrollContentBackground(.hidden).novaGlassBackdrop()
        .navigationTitle("Estate")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshAll() }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .refreshable { await refreshAll() }
        .task {
            freshness.refreshIfNeeded()
            estateStore.refreshIfNeeded()
        }
    }

    private func refreshAll() async {
        await freshness.refresh()
        await estateStore.refresh()
    }

    // MARK: - Nexus freshness (summary only; pipe detail lives in Data Sources)

    private var nexusSection: some View {
        Section {
            LabeledContent("Overall") {
                HStack(spacing: 6) {
                    Circle().fill(overallColor).frame(width: 10, height: 10)
                    Text(freshness.freshness.summary.overall)
                }
            }
            LabeledContent("Fresh / stale / error") {
                Text("\(freshness.freshness.summary.fresh) / \(freshness.freshness.summary.stale) / \(freshness.freshness.summary.error)")
            }
            LabeledContent("Worker queue") {
                Text(queueText)
            }
            if estateStore.estate.summary.totalOutdatedPackages > 0 {
                LabeledContent("Outdated packages") {
                    Text("\(estateStore.estate.summary.totalOutdatedPackages)")
                        .foregroundStyle(ARIATheme.accentGold)
                }
            }
        } header: {
            Text("Nexus").foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }

    private var queueText: String {
        let queue = freshness.freshness.platform.workerQueue
        guard let pending = queue.pending else { return queue.status }
        return "\(pending) pending · \(queue.status)"
    }

    private var overallColor: Color {
        switch freshness.freshness.summary.overall {
        case "ok": return ARIATheme.success
        case "degraded": return ARIATheme.accentGold
        case "error": return ARIATheme.error
        default: return ARIATheme.textMuted
        }
    }

    // MARK: - Per-host registry aggregates

    private func hostSection(_ host: MobileEstate.Host) -> some View {
        Section {
            LabeledContent("Registry synced") {
                HStack(spacing: 6) {
                    if host.registryStale {
                        Text("stale").font(.caption).foregroundStyle(ARIATheme.accentGold)
                    }
                    Text(syncedText(host))
                }
            }
            LabeledContent("Apps") {
                Text("\(host.apps.installed) installed · \(host.apps.running) running")
            }
            LabeledContent("Packages") {
                HStack(spacing: 6) {
                    Text("\(host.packages.total)")
                    if host.packages.outdated > 0 {
                        Text("· \(host.packages.outdated) outdated")
                            .foregroundStyle(ARIATheme.accentGold)
                    }
                }
            }
            LabeledContent("Services") {
                Text("\(host.services.running) of \(host.services.total) running")
            }
            LabeledContent("Actions") {
                Text("\(host.actions.total)")
            }
            NavigationLink {
                EstateHostDetailView(host: host)
            } label: {
                Text("Host details").foregroundStyle(ARIATheme.accentCyan)
            }
        } header: {
            Text(host.displayName).foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }

    private func syncedText(_ host: MobileEstate.Host) -> String {
        if let age = host.registryAgeS {
            if age < 90 { return "just now" }
            if age < 3600 { return "\(age / 60)m ago" }
            if age < 86400 { return "\(age / 3600)h ago" }
            return "\(age / 86400)d ago"
        }
        if let date = parseServerDate(host.registrySyncedAt) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return "never"
    }

    // MARK: - This iPhone (server-side row)

    private var thisPhoneSection: some View {
        Section {
            if let device = estateStore.thisDevice {
                LabeledContent("Model") { Text(device.model ?? "—") }
                LabeledContent("iOS") { Text(device.osVersion ?? "—") }
                LabeledContent("App") {
                    Text([device.appVersion, device.appBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                }
                LabeledContent("Channel") { Text(device.distribution ?? "—") }
                LabeledContent("Profile expires") {
                    Text(profileExpiryText(device))
                        .foregroundStyle(profileExpiryColor(device))
                }
                LabeledContent("Last seen by Nexus") {
                    Text(lastSeenText(device))
                }
            } else {
                Text("No registration on Nexus yet — it lands when this app next registers (Settings → This Device).")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
            }
        } header: {
            Text("This iPhone").foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }

    private func profileExpiryText(_ device: MobileEstate.Device) -> String {
        guard let date = parseServerDate(device.profileExpiresAt) else {
            return device.profileExpiresAt ?? "—"
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        return days >= 0 ? "\(formatted) (\(days)d)" : formatted
    }

    private func profileExpiryColor(_ device: MobileEstate.Device) -> Color {
        guard let date = parseServerDate(device.profileExpiresAt) else { return ARIATheme.textPrimary }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 999
        return days < 60 ? ARIATheme.accentGold : ARIATheme.textPrimary
    }

    private func lastSeenText(_ device: MobileEstate.Device) -> String {
        guard let date = parseServerDate(device.lastSeenAt) else { return device.lastSeenAt ?? "—" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
