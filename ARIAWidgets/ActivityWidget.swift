import SwiftUI
import WidgetKit

struct ActivityWidget: Widget {
    let kind = "ActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActivityProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Activity Status")
        .description("Current motion state and location.")
        .supportedFamilies([.systemSmall])
    }
}

struct ActivityEntry: TimelineEntry {
    let date: Date
    let activity: String?
    let location: String?
}

struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        ActivityEntry(date: .now, activity: "Walking", location: "Springfield")
    }

    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> ActivityEntry {
        if let status = WidgetDataService.readActivityStatus() {
            return ActivityEntry(date: .now, activity: status.activity, location: status.location.isEmpty ? nil : status.location)
        }
        return ActivityEntry(date: .now, activity: nil, location: nil)
    }
}

struct ActivityWidgetView: View {
    let entry: ActivityEntry

    private var activityIcon: String {
        switch entry.activity?.lowercased() {
        case "driving": return "car.fill"
        case "cycling": return "bicycle"
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "stationary": return "person.fill"
        default: return "questionmark.circle"
        }
    }

    private var activityColor: Color {
        switch entry.activity?.lowercased() {
        case "driving": return .blue
        case "cycling": return .orange
        case "running": return .red
        case "walking": return .green
        case "stationary": return WidgetTheme.textMuted
        default: return WidgetTheme.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
                Text("ACTIVITY")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.accentCyan)
                    .tracking(0.5)
            }
            .padding(.bottom, 8)

            if let activity = entry.activity {
                Spacer()

                Image(systemName: activityIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(activityColor)
                    .padding(.bottom, 4)

                Text(activity)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textPrimary)

                if let location = entry.location {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 8))
                        Text(location)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .padding(.top, 1)
                }

                Spacer()
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 20))
                        .foregroundStyle(WidgetTheme.textMuted)
                    Text("No data")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
