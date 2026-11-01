import SwiftUI

/// Per-host estate drill-down (upgrades-scan item 4, 3.4.0): the rows
/// behind the Estate tab's aggregates, from
/// GET /api/mobile/estate/hosts/:hostId. Answers "which packages are
/// outdated on the build Mac" from the phone. Fetched on demand; read-only.
struct EstateHostDetailView: View {
    let host: MobileEstate.Host

    @Environment(EstateStore.self) private var estateStore
    @State private var detail: MobileEstateHostDetail?
    @State private var failed = false

    var body: some View {
        List {
            if let detail {
                packagesSection(detail)
                appsSection(detail)
                servicesSection(detail)
                actionsSection(detail)
            } else if failed {
                Section {
                    Text("Couldn't load host detail — Nexus unreachable or the detail endpoint isn't live yet.")
                        .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
                .listRowBackground(ARIATheme.glassSurface)
            } else {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading \(host.displayName) detail…")
                            .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                    }
                }
                .listRowBackground(ARIATheme.glassSurface)
            }
        }
        .scrollContentBackground(.hidden).novaGlassBackdrop()
        .navigationTitle(host.displayName)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        if let fetched = await estateStore.hostDetail(host.host) {
            detail = fetched
        } else {
            failed = true
        }
    }

    // MARK: - Sections

    private func packagesSection(_ detail: MobileEstateHostDetail) -> some View {
        Section {
            if detail.packages.isEmpty {
                Text("No packages in this host's registry.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
            }
            ForEach(detail.packages) { pkg in
                HStack {
                    Text(pkg.name).foregroundStyle(ARIATheme.textPrimary)
                    Spacer()
                    if pkg.outdated {
                        Text("\(pkg.installedVersion ?? "?") → \(pkg.latestVersion ?? "?")")
                            .font(.caption).foregroundStyle(ARIATheme.accentGold)
                    } else {
                        Text(pkg.installedVersion ?? "—")
                            .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                    }
                }
            }
        } header: {
            Text("Packages (\(detail.packages.count))").foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }

    private func appsSection(_ detail: MobileEstateHostDetail) -> some View {
        Section {
            if detail.apps.isEmpty {
                Text("No apps in this host's registry.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
            }
            ForEach(detail.apps) { app in
                HStack(spacing: 8) {
                    Circle()
                        .fill(app.running ? ARIATheme.success : ARIATheme.textMuted)
                        .frame(width: 8, height: 8)
                    Text(app.displayName).foregroundStyle(ARIATheme.textPrimary)
                    Spacer()
                    if let version = app.version {
                        Text(version).font(.caption).foregroundStyle(ARIATheme.textSecondary)
                    }
                }
            }
        } header: {
            Text("Apps (\(detail.apps.count))").foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }

    private func servicesSection(_ detail: MobileEstateHostDetail) -> some View {
        Section {
            if detail.services.isEmpty {
                Text("No services in this host's registry.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
            }
            ForEach(detail.services) { service in
                LabeledContent(service.displayName) {
                    Text(service.desiredState ?? "—")
                        .foregroundStyle(ARIATheme.textSecondary)
                }
            }
        } header: {
            Text("Services (\(detail.services.count))").foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }

    private func actionsSection(_ detail: MobileEstateHostDetail) -> some View {
        Section {
            if detail.actions.isEmpty {
                Text("No recent actions recorded for this host.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
            }
            ForEach(detail.actions) { action in
                HStack {
                    Text(action.name ?? action.op ?? "action")
                        .foregroundStyle(ARIATheme.textPrimary)
                    Spacer()
                    if let at = action.updatedAt, let date = parseServerDate(at) {
                        Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                            .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                    }
                }
            }
        } header: {
            Text("Recent actions").foregroundStyle(ARIATheme.accentGold)
        }
        .listRowBackground(ARIATheme.glassSurface)
    }
}
