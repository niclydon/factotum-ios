import SwiftUI

/// Settings → Automations. The Shortcuts ingest pipe (Nexus side) has
/// been live since September, but nothing flows until personal
/// automations exist on this phone — and until 3.2.0 the only guide was
/// a markdown file in the repo. This screen carries the recipes in-app
/// and can prove the pipe end to end with one tap.
struct AutomationSetupView: View {
    @State private var events = DeviceEventSync.shared
    @State private var sending = false
    @State private var testResult: String?

    var body: some View {
        List {
            Section {
                Text("Shortcuts automations hand Factotum the events iOS won't let an app see directly: notifications, Wallet taps, app opens, Focus changes. Each automation runs one Factotum action; events queue on the phone and upload to Nexus.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                Button {
                    sending = true
                    Task {
                        testResult = await events.sendTestEvent()
                        sending = false
                    }
                } label: {
                    HStack {
                        Text(sending ? "Sending…" : "Send a test event")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(sending)
                if let testResult {
                    Text(testResult).font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
                LabeledContent("Queued") { Text("\(events.pendingCount)") }
                if events.deadLetterCount > 0 {
                    LabeledContent("Rejected") { Text("\(events.deadLetterCount)").foregroundStyle(ARIATheme.error) }
                }
            } header: {
                Text("Prove the pipe")
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                recipe(
                    title: "Notifications",
                    trigger: "Automation → + → Notification",
                    action: "Log Notification to ARIA",
                    steps: [
                        "Pick the app (or apps) whose notifications matter, then Next.",
                        "Choose Run Immediately so there's no confirmation prompt.",
                        "Add the action \"Log Notification to ARIA\".",
                        "Map its fields from the automation's variables: App, Title, and Body come from the incoming notification.",
                    ]
                )
                recipe(
                    title: "Wallet purchases",
                    trigger: "Automation → + → Transaction",
                    action: "Log Purchase to ARIA",
                    steps: [
                        "Pick the card (or Any Card), then Next, Run Immediately.",
                        "Add the action \"Log Purchase to ARIA\".",
                        "Card, Merchant, and Amount fill from the transaction variables automatically.",
                    ]
                )
                recipe(
                    title: "App opens & closes",
                    trigger: "Automation → + → App",
                    action: "Log App Event to ARIA",
                    steps: [
                        "Pick the app, choose Is Opened and/or Is Closed, then Next, Run Immediately.",
                        "Add the action \"Log App Event to ARIA\" and set State to match the trigger.",
                    ]
                )
                recipe(
                    title: "Focus, charger, CarPlay, NFC…",
                    trigger: "Automation → + → (trigger of choice)",
                    action: "Log Event to ARIA",
                    steps: [
                        "Create the automation for any other trigger, Run Immediately.",
                        "Add the action \"Log Event to ARIA\" and give it a short Label (e.g. \"Driving\", \"Charging\").",
                        "Optional Text or JSON fields ride along as structured data.",
                    ]
                )
            } header: {
                Text("Recipes")
            } footer: {
                Text("Events land in Nexus within a sweep or two and show up under Data Sources → Automations with per-automation counts.")
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            }
            .listRowBackground(ARIATheme.surface)
        }
        .scrollContentBackground(.hidden).background(ARIATheme.background)
        .navigationTitle("Automations")
        .task { await events.refreshSnapshot() }
    }

    @ViewBuilder
    private func recipe(title: String, trigger: String, action: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(ARIATheme.textPrimary)
            Text(trigger).font(.caption).foregroundStyle(ARIATheme.accentGold)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(.caption)
                    .foregroundStyle(ARIATheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
