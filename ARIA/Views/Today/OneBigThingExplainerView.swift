import SwiftUI

/// How the One Big Thing composite is computed (Factotum 4.0 W3 explainer,
/// owed from Slice A). Static, honest text: the same weights and windows
/// the server builder uses, including what the numbers are NOT.
struct OneBigThingExplainerView: View {
    var body: some View {
        List {
            Section {
                Text("One Big Thing turns last night and the recent past into three numbers on Today. Every input is yours, every baseline is your own history, and nothing here compares you to anyone else.")
                    .foregroundStyle(ARIATheme.textSecondary)
            }

            Section("Readiness (0–100)") {
                Text("How recovered you look this morning, scored against your own trailing 28-day baselines (at least 7 samples or the input is skipped and the rest re-weight). 70 means exactly at your baseline.")
                bullet("Sleep duration · 28%")
                bullet("Sleep efficiency · 14%")
                bullet("Resting heart rate · 19% (lower is better)")
                bullet("HRV · 19% (higher is better)")
                bullet("Strain · 20% (active energy + exercise vs your norm)")
                Text("The card's confidence reflects how many inputs were actually available.")
                    .foregroundStyle(ARIATheme.textSecondary)
            }

            Section("Cumulative stress (31 days)") {
                Text("A slower gauge: how much load has accumulated over the last 31 days. Five contributors, each visible on the card with its share.")
                bullet("Sleep debt")
                bullet("Resting heart rate drift")
                bullet("HRV drift")
                bullet("Strain load (acute vs chronic workload)")
                bullet("Travel disruption (days away, from your visits)")
            }

            Section("Body-age index") {
                Text("Not an age in years, and deliberately so. It is a delta index: your last 30 days of resting heart rate, HRV, sleep, and activity compared with your own prior 90 days. Negative means your recent physiology trends younger than your own baseline; positive means older. Anyone who converts that into a literal age is inventing precision the data does not have.")
                    .foregroundStyle(ARIATheme.textPrimary)
            }

            Section("What it is not") {
                Text("Not a medical measurement, not a diagnosis, and not a comparison to population norms. If an input has no recent data, it says so on the card instead of guessing.")
                    .foregroundStyle(ARIATheme.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ARIATheme.background)
        .navigationTitle("About One Big Thing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").foregroundStyle(ARIATheme.textMuted)
            Text(text).foregroundStyle(ARIATheme.textPrimary)
        }
    }
}
