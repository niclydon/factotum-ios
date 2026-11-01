import SwiftUI

/// Root once authenticated: Today (glance) · Review (card queue) · Ask (read-only Q&A) · Chat.
/// Spec: docs/superpowers/specs/2026-09-06-review-tab-and-today-design.md §3.
struct RootTabView: View {
    @State private var selection: TabItem = .today
    @State private var reviewPath: [ReviewCard] = []
    @Environment(DeepLinkManager.self) private var deepLink
    @Environment(ReviewStore.self) private var review

    enum TabItem: Hashable { case today, review, ask, chat, replay, estate }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView(onOpenReview: { selection = .review }) }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(TabItem.today)

            NavigationStack(path: $reviewPath) {
                ReviewListView()
                    .navigationDestination(for: ReviewCard.self) { ReviewDetailView(card: $0) }
            }
            .tabItem { Label("Review", systemImage: "checkmark.rectangle.stack") }
            .badge(review.openCount)
            .tag(TabItem.review)

            NavigationStack { AskView() }
                .tabItem { Label("Ask", systemImage: "sparkles") }
                .tag(TabItem.ask)

            NavigationStack { ChatView() }
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(TabItem.chat)

            NavigationStack { ReplayView() }
                .tabItem { Label("Replay", systemImage: "clock.arrow.circlepath") }
                .tag(TabItem.replay)
            NavigationStack { EstateTabView() }
                .tabItem { Label("Estate", systemImage: "building.2") }
                .tag(TabItem.estate)
        }
        .tint(ARIATheme.accent)
        .task { await review.loadIfStale() }
        .onChange(of: deepLink.pendingTab) { _, tab in
            guard let tab else { return }
            deepLink.pendingTab = nil
            switch tab {
            case "today": selection = .today
            case "review": selection = .review
            case "ask": selection = .ask
            case "chat": selection = .chat
            case "replay": selection = .replay
            case "estate": selection = .estate
            default: break
            }
        }
        .onChange(of: deepLink.pendingSettingsPage) { _, page in
            // Settings is presented from Today's toolbar; bring Today forward
            // and let TodayView open the sheet.
            if page != nil { selection = .today }
        }
        .onChange(of: deepLink.pendingReviewCardId) { _, id in
            guard let id else { return }
            deepLink.pendingReviewCardId = nil
            Task { await openReviewCard(id) }
        }
    }

    private func openReviewCard(_ id: String) async {
        guard !id.isEmpty else { selection = .review; return }
        await review.load()
        selection = .review
        if let card = review.open.first(where: { $0.id == id }) ?? review.recent.first(where: { $0.id == id }) {
            reviewPath = [card]
        }
    }
}

