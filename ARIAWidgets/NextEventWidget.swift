import SwiftUI
import WidgetKit

struct NextEventWidget: Widget {
    let kind = "NextEventWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextEventProvider()) { entry in
            NextEventWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("Your next calendar event with countdown.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextEventEntry: TimelineEntry {
    let date: Date
    let eventTitle: String?
    let eventStart: Date?
    let eventEnd: Date?
    let location: String?
}

struct NextEventProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEventEntry {
        NextEventEntry(date: .now, eventTitle: "Team Meeting", eventStart: .now.addingTimeInterval(3600), eventEnd: nil, location: "Conference Room")
    }

    func getSnapshot(in context: Context, completion: @escaping (NextEventEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextEventEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> NextEventEntry {
        if let event = WidgetDataService.readNextEvent() {
            return NextEventEntry(date: .now, eventTitle: event.title, eventStart: event.startDate, eventEnd: event.endDate, location: event.location.isEmpty ? nil : event.location)
        }
        return NextEventEntry(date: .now, eventTitle: nil, eventStart: nil, eventEnd: nil, location: nil)
    }
}

struct NextEventWidgetView: View {
    let entry: NextEventEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
                Text("NEXT UP")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.accentCyan)
                    .tracking(0.5)
            }
            .padding(.bottom, 8)

            if let title = entry.eventTitle, let start = entry.eventStart {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(2)
                    .padding(.bottom, 4)

                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(WidgetTheme.accentCyan)
                    Text(start, style: .relative)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.accentCyan)
                }
                .padding(.bottom, 2)

                if let location = entry.location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                            .foregroundStyle(WidgetTheme.textMuted)
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20))
                        .foregroundStyle(WidgetTheme.textMuted)
                    Text("All clear")
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
}
