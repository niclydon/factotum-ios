import SwiftUI

/// Settings → Trust Ledger (Factotum 4.0 W7, first slice). Three answers,
/// always current: what the server last heard from each pipe, what this
/// device last did per sync lane, and everything the on-device AI has
/// done, including exactly what left the phone. Battery attribution
/// (MetricKit) completes the ledger in 4.1.
struct TrustLedgerView: View {
    @Environment(FreshnessStore.self) private var freshnessStore
    @State private var aiEntries: [AIActivityEntry] = []
    @State private var laneSnapshot = SyncFreshness.load()

    var body: some View {
        List {
            Section {
                Text("Every pipe, every on-device AI run, and exactly what left this phone. If a number here disagrees with the server, the disagreement is the finding.")
                    .font(.footnote)
                    .foregroundStyle(ARIATheme.textSecondary)
            }

            Section("Server freshness") {
                if freshnessStore.isFetching {
                    HStack { ProgressView(); Text("Checking the registry…") }
                        .foregroundStyle(ARIATheme.textSecondary)
                }
                if !freshnessStore.hasServerSnapshot {
                    Text("No server snapshot yet; showing defaults until the first check completes.")
                        .font(.caption)
                        .foregroundStyle(ARIATheme.textMuted)
                }
                LabeledContent("Fresh / stale / error",
                               value: "\(freshnessStore.freshness.summary.fresh) / \(freshnessStore.freshness.summary.stale) / \(freshnessStore.freshness.summary.error)")
                ForEach(freshnessStore.freshness.sources) { source in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.displayLabel)
                                .foregroundStyle(ARIATheme.textPrimary)
                            Text(source.userFacingState.capitalized)
                                .font(.caption)
                                .foregroundStyle(ARIATheme.textMuted)
                        }
                        Spacer()
                        Text(source.lastSeenDate.map {
                            RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())
                        } ?? "never")
                            .font(.caption)
                            .foregroundStyle(ARIATheme.textSecondary)
                    }
                }
            }

            Section("Sync lanes on this device") {
                if laneSnapshot.sources.isEmpty {
                    Text("No lane activity recorded yet.")
                        .foregroundStyle(ARIATheme.textSecondary)
                }
                ForEach(laneSnapshot.sources.sorted(by: { $0.key < $1.key }), id: \.key) { lane, date in
                    LabeledContent(lane) {
                        Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                            .foregroundStyle(ARIATheme.textSecondary)
                    }
                }
                if let background = laneSnapshot.lastBackgroundRun {
                    LabeledContent("Last background run") {
                        Text(RelativeDateTimeFormatter().localizedString(for: background, relativeTo: Date()))
                            .foregroundStyle(ARIATheme.textSecondary)
                    }
                }
            }

            Section("On-device AI log") {
                if aiEntries.isEmpty {
                    Text("Nothing yet. Lens analysis and the morning paragraph will appear here as they run.")
                        .foregroundStyle(ARIATheme.textSecondary)
                }
                ForEach(aiEntries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(Self.kindLabel(entry.kind))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ARIATheme.textPrimary)
                            Spacer()
                            Text(RelativeDateTimeFormatter().localizedString(for: entry.at, relativeTo: Date()))
                                .font(.caption)
                                .foregroundStyle(ARIATheme.textMuted)
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(ARIATheme.textSecondary)
                        Text(entry.leftDevice > 0
                             ? "\(entry.leftDevice) record(s) left the device"
                             : "Nothing left the device")
                            .font(.caption)
                            .foregroundStyle(entry.leftDevice > 0 ? ARIATheme.textSecondary : ARIATheme.textMuted)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ARIATheme.background)
        .navigationTitle("Trust Ledger")
        .task {
            aiEntries = AIActivityLog.entries()
            laneSnapshot = SyncFreshness.load()
            await freshnessStore.refresh()
        }
    }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "lens.analyze": return "Lens analysis"
        case "lens.upload": return "Lens upload"
        case "brief.generate": return "Morning paragraph"
        default: return kind
        }
    }
}
