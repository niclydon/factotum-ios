import SwiftUI

/// Data Sources → Health Records & ECG detail. The clinical pipe is the
/// quietest one in the app (records change rarely), so it gets its own
/// screen: connection state, last sync, and exactly what the last sync
/// sent — the detail that proves the pipe works when months pass
/// between new records.
struct HealthFilesDetailView: View {
    @State private var healthFiles = HealthFilesSync.shared

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Connected") { Text(healthFiles.isEnabled ? "Yes" : "No") }
                LabeledContent("Last synced") {
                    Text(healthFiles.lastSyncDate.map {
                        RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())
                    } ?? "never")
                }
                if let error = healthFiles.syncError {
                    Text(error).font(.caption).foregroundStyle(ARIATheme.error).textSelection(.enabled)
                }
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                if let result = healthFiles.lastResult {
                    LabeledContent("Clinical records") { Text("\(result.clinical)") }
                    LabeledContent("ECGs") { Text("\(result.ecg)") }
                    LabeledContent("Workout routes") { Text("\(result.routes)") }
                    LabeledContent("Sent at") {
                        Text(RelativeDateTimeFormatter().localizedString(for: result.at, relativeTo: Date()))
                    }
                } else {
                    Text("No sync has completed yet on this device, or the last one sent nothing new.")
                        .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
            } header: {
                Text("Last sync sent")
            } footer: {
                Text("Counts are what this phone uploaded, not Nexus totals. Zero is normal — clinical records only change when a provider adds something.")
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                Button {
                    Task { await healthFiles.sync() }
                } label: {
                    HStack {
                        Text(healthFiles.isSyncing ? "Syncing…" : "Sync now")
                        if healthFiles.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(healthFiles.isSyncing || !healthFiles.isEnabled)
                if !healthFiles.isEnabled {
                    Button("Connect") { Task { await healthFiles.requestAuthorization() } }
                }
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                Text("Clinical records (conditions, labs, medications, immunizations), ECGs from Apple Watch, and workout route maps, read from the Health app and uploaded to Nexus. This is separate from the minute-by-minute Health sync — it moves documents, not samples.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
            }
            .listRowBackground(ARIATheme.surface)
        }
        .scrollContentBackground(.hidden).background(ARIATheme.background)
        .navigationTitle("Health Records & ECG")
    }
}
