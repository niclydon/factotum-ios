import SwiftUI
import WidgetKit

struct LargeWidget: Widget {
    let kind = "LargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LargeProvider()) { entry in
            LargeWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Factotum Full Dashboard")
        .description("Complete overview: event, health, and activity.")
        .supportedFamilies([.systemLarge])
    }
}

struct LargeEntry: TimelineEntry {
    let date: Date
    let eventTitle: String?
    let eventStart: Date?
    let steps: Int?
    let sleepHours: Double?
    let heartRate: Int?
    let activeCalories: Int?
    let distance: Double?
    let activity: String?
    let location: String?
    let lastSyncDetail: String?
    let updateAvailable: Bool
}

struct LargeProvider: TimelineProvider {
    func placeholder(in context: Context) -> LargeEntry {
        LargeEntry(date: .now, eventTitle: "Team Meeting", eventStart: .now.addingTimeInterval(3600), steps: 6432, sleepHours: 7.2, heartRate: 62, activeCalories: 340, distance: 3.1, activity: "Walking", location: "Springfield", lastSyncDetail: "synced 5 minutes ago", updateAvailable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (LargeEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LargeEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> LargeEntry {
        let event = WidgetDataService.readNextEvent()
        let health = WidgetDataService.readHealthSummary()
        let activity = WidgetDataService.readActivityStatus()
        return LargeEntry(
            date: .now,
            eventTitle: event?.title,
            eventStart: event?.startDate,
            steps: health?.steps,
            sleepHours: health?.sleepHours,
            heartRate: health?.heartRate,
            activeCalories: health?.activeCalories,
            distance: health?.distance,
            activity: activity?.activity,
            location: activity?.location.isEmpty == true ? nil : activity?.location,
            lastSyncDetail: WidgetDataService.readFreshness().lastSyncDetail,
            updateAvailable: WidgetDataService.readFreshness().updateAvailable
        )
    }
}

struct LargeWidgetView: View {
    let entry: LargeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 5) {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
                Text("FACTOTUM")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.accentCyan)
                    .tracking(0.5)
                Spacer()
                if entry.updateAvailable {
                    Text("Update available")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                } else if let detail = entry.lastSyncDetail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Next Event
            if let title = entry.eventTitle, let start = entry.eventStart {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(1)
                        Text(start, style: .relative)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetTheme.accentCyan)
                    }
                }
            }

            // Health Grid
            HStack(spacing: 12) {
                if let steps = entry.steps {
                    metricPill(icon: "figure.walk", color: .green, value: steps.formatted(), label: "steps")
                }
                if let sleep = entry.sleepHours {
                    metricPill(icon: "moon.fill", color: .indigo, value: String(format: "%.1f", sleep), label: "hrs")
                }
                if let hr = entry.heartRate {
                    metricPill(icon: "heart.fill", color: .red, value: "\(hr)", label: "bpm")
                }
                if let cal = entry.activeCalories {
                    metricPill(icon: "flame.fill", color: .orange, value: "\(cal)", label: "cal")
                }
            }

            // Activity
            if let activity = entry.activity {
                HStack(spacing: 6) {
                    Image(systemName: activityIcon(activity))
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text(activity)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.textPrimary)
                    if let location = entry.location {
                        Text("· \(location)")
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            // Interactive sync (3.4.0), same aria://sync route as the
            // medium dashboard widget.
            HStack {
                Spacer()
                Link(destination: URL(string: "aria://sync")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                        Text("Sync now")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(WidgetTheme.accentCyan)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func metricPill(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(WidgetTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(WidgetTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func activityIcon(_ activity: String) -> String {
        switch activity.lowercased() {
        case "driving": return "car.fill"
        case "cycling": return "bicycle"
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        default: return "person.fill"
        }
    }
}
