import SwiftUI

struct SleepCard: View {
    let state: Loadable<(SleepNightlyProfile, SleepRecoveryProfile?)>
    var body: some View {
        TodayCard(title: "Sleep", icon: "moon.zzz") {
            LoadableBody(state: state, emptyText: "No sleep data yet") { (nightly, recovery) in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    stat(String(format: "%.1f h", nightly.lastNight?.value ?? 0), "last night")
                    if let e = nightly.lastEfficiency { stat(String(format: "%.0f%%", e), "efficiency") }
                    if let r = recovery?.latestScore { stat(String(format: "%.0f", r), "recovery") }
                }
                if let h = recovery?.latestReadiness?.headline { Text(h).font(.caption).foregroundStyle(ARIATheme.textSecondary) }
                if let d = nightly.lastNight?.date { Text(d).font(.caption2).foregroundStyle(ARIATheme.textMuted) }
            }
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(ARIATheme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(ARIATheme.textMuted)
        }
    }
}
