import SwiftUI

struct PlacesTimelineCard: View {
    let state: Loadable<([Visit], [TimelineEvent])>
    var body: some View {
        TodayCard(title: "Places & timeline", icon: "map") {
            LoadableBody(state: state, emptyText: "Nothing logged yet today") { (visits, events) in
                if !visits.isEmpty {
                    Text("\(visits.count) place\(visits.count == 1 ? "" : "s") visited").font(.caption).foregroundStyle(ARIATheme.textSecondary)
                }
                ForEach(events.prefix(6)) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.time(e.eventTime)).font(.caption2).monospacedDigit().foregroundStyle(ARIATheme.textMuted).frame(width: 44, alignment: .leading)
                        Text(e.title ?? e.summary ?? ReviewCard.humanise(e.eventType ?? "event")).font(.caption).foregroundStyle(ARIATheme.textPrimary).lineLimit(2)
                    }
                }
            }
        }
    }
    static func time(_ iso: String?) -> String {
        guard let d = RelativeAge.parse(iso) else { return "" }
        return d.formatted(date: .omitted, time: .shortened)
    }
}
