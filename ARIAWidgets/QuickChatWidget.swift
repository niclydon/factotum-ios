import SwiftUI
import WidgetKit

struct QuickChatWidget: Widget {
    let kind = "QuickChatWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickChatProvider()) { entry in
            QuickChatWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Ask ARIA")
        .description("Tap to start a conversation with ARIA.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickChatEntry: TimelineEntry {
    let date: Date
}

struct QuickChatProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickChatEntry { QuickChatEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickChatEntry) -> Void) { completion(QuickChatEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickChatEntry>) -> Void) {
        completion(Timeline(entries: [QuickChatEntry(date: .now)], policy: .after(.now.addingTimeInterval(21600))))
    }
}

struct QuickChatWidgetView: View {
    let entry: QuickChatEntry

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            Image("ARIAProfile")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(WidgetTheme.accentCyan.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: WidgetTheme.accentCyan.opacity(0.2), radius: 8)

            Text("Ask ARIA")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)

            Text("Tap to chat")
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.textMuted)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
