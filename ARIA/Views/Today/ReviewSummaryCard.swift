import SwiftUI

struct ReviewSummaryCard: View {
    let store: ReviewStore
    let onOpen: () -> Void
    var body: some View {
        TodayCard(title: "Review", icon: "checkmark.rectangle.stack") {
            if store.openCount == 0 {
                Text("Nothing waiting").font(.caption).foregroundStyle(ARIATheme.textMuted)
            } else {
                Text(store.openByDomain.map { "\($0.cards.count) \(ReviewCard.domainTitle($0.domain).lowercased())" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                ForEach(Array(store.open.prefix(3))) { card in
                    HStack {
                        Text(card.title).font(.subheadline).foregroundStyle(ARIATheme.textPrimary).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(ARIATheme.textMuted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen() }
                }
                Button("Open Review (\(store.openCount))", action: onOpen).font(.caption.weight(.semibold)).foregroundStyle(ARIATheme.accent)
            }
        }
    }
}
