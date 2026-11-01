import SwiftUI
import WidgetKit

struct HealthWidget: Widget {
    let kind = "HealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthProvider()) { entry in
            HealthWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Health Today")
        .description("Today's health snapshot at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

struct HealthEntry: TimelineEntry {
    let date: Date
    let steps: Int?
    let sleepHours: Double?
    let heartRate: Int?
    let activeCalories: Int?
}

struct HealthProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        HealthEntry(date: .now, steps: 6432, sleepHours: 7.2, heartRate: 62, activeCalories: 340)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> HealthEntry {
        if let health = WidgetDataService.readHealthSummary() {
            return HealthEntry(date: .now, steps: health.steps, sleepHours: health.sleepHours, heartRate: health.heartRate, activeCalories: health.activeCalories)
        }
        return HealthEntry(date: .now, steps: nil, sleepHours: nil, heartRate: nil, activeCalories: nil)
    }
}

struct HealthWidgetView: View {
    let entry: HealthEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
                Text("HEALTH")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.accentCyan)
                    .tracking(0.5)
            }
            .padding(.bottom, 8)

            if entry.steps != nil || entry.sleepHours != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let steps = entry.steps {
                        metricRow(icon: "figure.walk", color: .green, value: steps.formatted(), unit: "steps")
                    }
                    if let sleep = entry.sleepHours {
                        metricRow(icon: "moon.fill", color: .indigo, value: String(format: "%.1f", sleep), unit: "hrs sleep")
                    }
                    if let hr = entry.heartRate {
                        metricRow(icon: "heart.fill", color: .red, value: "\(hr)", unit: "bpm")
                    }
                    if let cal = entry.activeCalories {
                        metricRow(icon: "flame.fill", color: .orange, value: "\(cal)", unit: "cal")
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.system(size: 20))
                        .foregroundStyle(WidgetTheme.textMuted)
                    Text("No data yet")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(icon: String, color: Color, value: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.textMuted)
        }
    }
}
