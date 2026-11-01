import SwiftUI

struct ActivityCard: View {
    let state: Loadable<(ActivityDailyProfile, [WorkoutListItem])>
    let todayKey: String
    var body: some View {
        TodayCard(title: "Activity", icon: "figure.walk") {
            LoadableBody(state: state, emptyText: "No activity yet today") { (daily, workouts) in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    stat(daily.today("steps", todayKey: todayKey).map { String(format: "%.0f", $0) } ?? "—", "steps")
                    stat(daily.today("exercise_minutes", todayKey: todayKey).map { String(format: "%.0f m", $0) } ?? "—", "exercise")
                    stat(daily.today("active_calories", todayKey: todayKey).map { String(format: "%.0f", $0) } ?? "—", "active kcal")
                }
                if let w = workouts.first {
                    Text("\(w.title ?? ReviewCard.humanise(w.workoutType ?? "workout")) · \(Int(w.durationMinutes ?? 0)) min")
                        .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
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
