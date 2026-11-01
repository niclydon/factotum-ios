import SwiftUI
import WidgetKit

struct DashboardWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardProvider()) { entry in
            DashboardWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Factotum Dashboard")
        .description("Combined view: next event and health.")
        .supportedFamilies([.systemMedium])
    }
}

struct DashboardEntry: TimelineEntry {
    let date: Date
    let eventTitle: String?
    let eventStart: Date?
    let steps: Int?
    let sleepHours: Double?
    let heartRate: Int?
    let freshnessOverall: String?
    let lastSyncDetail: String?
    let updateAvailable: Bool
}

struct DashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: .now, eventTitle: "Team Meeting", eventStart: .now.addingTimeInterval(3600), steps: 6432, sleepHours: 7.2, heartRate: 62, freshnessOverall: "ok", lastSyncDetail: "synced 5 minutes ago", updateAvailable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> DashboardEntry {
        let event = WidgetDataService.readNextEvent()
        let health = WidgetDataService.readHealthSummary()
        let freshness = WidgetDataService.readFreshness()
        return DashboardEntry(date: .now, eventTitle: event?.title, eventStart: event?.startDate, steps: health?.steps, sleepHours: health?.sleepHours, heartRate: health?.heartRate, freshnessOverall: freshness.overall, lastSyncDetail: freshness.lastSyncDetail, updateAvailable: freshness.updateAvailable)
    }
}

struct DashboardWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left column
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 5) {
                    Image("ARIAProfile")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    Text("FACTOTUM")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(WidgetTheme.accentCyan)
                        .tracking(0.5)
                }

                // Next event
                if let title = entry.eventTitle, let start = entry.eventStart {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(WidgetTheme.accentCyan)
                            Text(start, style: .relative)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WidgetTheme.accentCyan)
                        }
                    }
                }

                if entry.updateAvailable {
                    statusLine(color: .orange, text: "Update available")
                } else if let detail = entry.lastSyncDetail {
                    statusLine(color: entry.freshnessOverall == "ok" ? .green : .yellow, text: detail)
                }

                // Interactive sync (3.4.0): routes aria://sync, which the
                // app handles by running a sweep — one tap from the home
                // screen instead of opening the app and finding the button.
                Link(destination: URL(string: "aria://sync")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("Sync now")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(WidgetTheme.accentCyan)
                }

                Spacer(minLength: 0)
            }

            // Right column — health metrics
            VStack(alignment: .trailing, spacing: 6) {
                Spacer(minLength: 0)

                if let steps = entry.steps {
                    metricPill(icon: "figure.walk", color: .green, value: steps.formatted())
                }
                if let sleep = entry.sleepHours {
                    metricPill(icon: "moon.fill", color: .indigo, value: String(format: "%.1fh", sleep))
                }
                if let hr = entry.heartRate {
                    metricPill(icon: "heart.fill", color: .red, value: "\(hr)")
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusLine(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private func metricPill(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WidgetTheme.surface)
        .clipShape(Capsule())
    }
}
