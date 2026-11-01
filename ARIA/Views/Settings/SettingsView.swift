import SwiftUI

// Settings was substantially trimmed on 2026-04-26 alongside the Phase 5
// Nexus cutover. The iOS app's role post-cutover is sensor pipeline only:
// HealthKit, Core Location, Core Motion (plus MusicKit, re-wired 2026-05-16).
// Everything else either lives on Desk (chat, agent settings, inbox, reports,
// journal, knowledge graph) or is sourced server-side from upstream APIs
// (Calendar/Contacts via Google). The hidden services were later
// deleted outright (Contacts/Calendar/Reminders/HomeKit/Proactive 2026-07-15,
// Geofences 2026-09-25); reviving one means a deliberately-designed Nexus
// route first (docs/nexus-data-contract.md §4), then the service and screen.

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(DeepLinkManager.self) private var deepLink
    @State private var path: [DeepLinkManager.SettingsPage] = []
    @State private var updater = UpdateChecker.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var layout

    @ViewBuilder
    private var updateRow: some View {
        switch updater.state {
        case .available(let version):
            Link(destination: AppConfig.otaInstallURL) {
                HStack {
                    Label("Update available: \(version)", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(ARIATheme.accentGold)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(ARIATheme.textMuted)
                }
            }
        case .required(let minimum):
            VStack(alignment: .leading, spacing: 6) {
                Label("Update required — Nexus needs \(minimum) or later", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(ARIATheme.error)
                Link("Install the update", destination: AppConfig.otaInstallURL)
            }
        case .upToDate:
            LabeledContent("Updates") {
                Text("Up to date").foregroundStyle(ARIATheme.textSecondary)
            }
        case .checking:
            LabeledContent("Updates") { ProgressView() }
        case .failed:
            Button("Check for updates (couldn't reach the update server)") {
                Task { await updater.refresh(manual: true) }
            }
        case .unknown:
            Button("Check for updates") {
                Task { await updater.refresh(manual: true) }
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ARIATheme.background.ignoresSafeArea()

                List {
                    Section("Account") {
                        HStack(spacing: 12) {
                            if let avatarURLString = auth.gitHubAvatarURL,
                               let avatarURL = URL(string: avatarURLString) {
                                AsyncImage(url: avatarURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image("ARIAProfile")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            } else {
                                Image("ARIAProfile")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                if let username = auth.gitHubUsername {
                                    Text(username)
                                        .font(layout.adaptiveTitleFont)
                                        .foregroundStyle(ARIATheme.textPrimary)
                                }
                                Text("Signed in with GitHub")
                                    .font(layout.adaptiveCaptionFont)
                                    .foregroundStyle(ARIATheme.textSecondary)
                            }
                        }
                        .listRowBackground(ARIATheme.surface)

                        LabeledContent("Server") {
                            Text(auth.serverURL)
                                .font(layout.adaptiveCaptionFont)
                                .foregroundStyle(ARIATheme.textSecondary)
                        }
                        .listRowBackground(ARIATheme.surface)

                    }

                    Section("Data Sources") {
                        NavigationLink {
                            DataSourcesView()
                        } label: {
                            Label("Data Sources", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                        NavigationLink {
                            LensSettingsView()
                        } label: {
                            Label("Lens", systemImage: "camera.aperture")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                        NavigationLink {
                            TrustLedgerView()
                        } label: {
                            Label("Trust Ledger", systemImage: "checkmark.shield")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                    }
                    .listRowBackground(ARIATheme.surface)

                    Section("App") {
                        updateRow
                        NavigationLink(value: DeepLinkManager.SettingsPage.device) {
                            Label("This Device", systemImage: "iphone")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                        Button {
                            deepLink.pendingTab = "estate"
                            dismiss()
                        } label: {
                            Label("Estate", systemImage: "building.2")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                        NavigationLink(value: DeepLinkManager.SettingsPage.automations) {
                            Label("Automations", systemImage: "bolt.horizontal.circle")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                        NavigationLink(value: DeepLinkManager.SettingsPage.diagnostics) {
                            Label("Diagnostics", systemImage: "stethoscope")
                                .foregroundStyle(ARIATheme.textPrimary)
                        }
                    }
                    .listRowBackground(ARIATheme.surface)

                    Section {
                        Button("Sign Out", role: .destructive) {
                            auth.logout()
                            dismiss()
                        }
                    }
                    .listRowBackground(ARIATheme.surface)

                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image("ARIAProfile")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                Text("Factotum v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                                    .font(layout.adaptiveCaptionFont)
                                    .foregroundStyle(ARIATheme.textMuted)
                                Text("Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
                                    .font(.system(size: layout.sized(phone: 10, pad: 12)))
                                    .foregroundStyle(ARIATheme.textMuted)
                                Text("Built by the author with AI assistance")
                                    .font(.system(size: layout.sized(phone: 10, pad: 12)))
                                    .foregroundStyle(Color(white: 0.33))
                            }
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .navigationDestination(for: DeepLinkManager.SettingsPage.self) { page in
                switch page {
                case .root: EmptyView()
                case .device: DeviceView()
                case .dataSources: DataSourcesView()
                case .diagnostics: DiagnosticsView()
                case .automations: AutomationSetupView()
                }
            }
            .onAppear {
                if let page = deepLink.pendingSettingsPage {
                    deepLink.pendingSettingsPage = nil
                    if page != .root { path = [page] }
                }
                updater.refreshIfNeeded()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ARIATheme.accent)
                }
            }
        }
    }
}
