import SwiftUI
import WidgetKit

// MARK: - Lock Screen Widget Bundle

struct LockScreenWidgets: Widget {
    let kind = "LockScreenWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("ARIA Quick Glance")
        .description("Next event or health snapshot on your Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let eventTitle: String?
    let eventStart: Date?
    let steps: Int?
    let heartRate: Int?
}

struct LockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: .now, eventTitle: "Meeting", eventStart: .now.addingTimeInterval(3600), steps: 6432, heartRate: 62)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> LockScreenEntry {
        let event = WidgetDataService.readNextEvent()
        let health = WidgetDataService.readHealthSummary()
        return LockScreenEntry(
            date: .now,
            eventTitle: event?.title,
            eventStart: event?.startDate,
            steps: health?.steps,
            heartRate: health?.heartRate
        )
    }
}

// MARK: - Lock Screen Views

struct LockScreenWidgetView: View {
    let entry: LockScreenEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            Text("FACTOTUM")
        }
    }

    // Rectangular: shows event or health
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                Text("FACTOTUM")
                    .font(.system(size: 10, weight: .heavy))
            }

            if let title = entry.eventTitle, let start = entry.eventStart {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(start, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let steps = entry.steps {
                HStack(spacing: 8) {
                    Label("\(steps.formatted())", systemImage: "figure.walk")
                        .font(.system(size: 12, weight: .medium))
                    if let hr = entry.heartRate {
                        Label("\(hr)", systemImage: "heart.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            } else {
                Text("All clear")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Circular: steps count or event countdown
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                if let steps = entry.steps {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10))
                    Text(abbreviateNumber(steps))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14))
                    Text("FACTOTUM")
                        .font(.system(size: 9, weight: .bold))
                }
            }
        }
    }

    // Inline: single line summary
    private var inlineView: some View {
        if let title = entry.eventTitle, let start = entry.eventStart {
            Label {
                Text("\(title) in \(start, style: .relative)")
            } icon: {
                Image(systemName: "calendar")
            }
        } else if let steps = entry.steps {
            Label {
                Text("\(steps.formatted()) steps")
            } icon: {
                Image(systemName: "figure.walk")
            }
        } else {
            Label("FACTOTUM", systemImage: "sparkle")
        }
    }

    private func abbreviateNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }
}
