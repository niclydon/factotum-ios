// ARIA/Services/ReviewStore.swift
import Foundation

enum ReviewDecideOutcome: Equatable, Sendable {
    case decided(ReviewCard)
    case conflict(ReviewCard)
    case noteRequired(String)
    case failed(String)
}

/// Open + recent review cards from Nexus; the Review tab's single source of truth and the tab badge.
/// Refreshes on tab appear (if stale), pull-to-refresh, after each decision, and from the
/// background sweep. Spec §2.
@Observable
@MainActor
final class ReviewStore {
    static let shared = ReviewStore()

    private(set) var open: [ReviewCard] = []
    private(set) var recent: [ReviewCard] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastLoadedAt: Date?

    var openCount: Int { open.count }

    var openByDomain: [(domain: String, cards: [ReviewCard])] { Self.group(open) }

    nonisolated static func group(_ cards: [ReviewCard]) -> [(domain: String, cards: [ReviewCard])] {
        Dictionary(grouping: cards, by: \.domain)
            .map { (domain: $0.key, cards: $0.value) }
            .sorted { a, b in
                let ra = ReviewCard.domainOrder.firstIndex(of: a.domain) ?? Int.max
                let rb = ReviewCard.domainOrder.firstIndex(of: b.domain) ?? Int.max
                return ra == rb ? a.domain < b.domain : ra < rb
            }
    }

    func loadIfStale(maxAge: TimeInterval = 600) async {
        if let at = lastLoadedAt, Date().timeIntervalSince(at) < maxAge, !open.isEmpty { return }
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let o = APIClient.shared.getReviewCards(status: .open)
            async let r = APIClient.shared.getReviewCards(status: .recent)
            let (openResp, recentResp) = try await (o, r)
            open = openResp.cards
            recent = recentResp.cards
            lastError = nil
            lastLoadedAt = Date()
            Logger.shared.log("review", "loaded open=\(open.count) recent=\(recent.count)")
        } catch {
            // Cancellation (a .task torn down by a tab switch) is not a
            // load failure; leave lastError and the loaded cards alone.
            let cancelled = error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || Task.isCancelled
            if !cancelled {
                lastError = error.localizedDescription
                Logger.shared.logMinimal("review", "load failed:", error.localizedDescription)
            }
        }
    }

    /// Optimistic: drop the card from `open` on success/conflict, prepend it to `recent`.
    func decide(id: String, decision: String, note: String?, selectedValues: [String] = []) async -> ReviewDecideOutcome {
        do {
            let card = try await APIClient.shared.decideReviewCard(id: id, decision: decision, note: note, selectedValues: selectedValues)
            settle(card)
            return .decided(card)
        } catch {
            let outcome = Self.outcome(for: error)
            if case .conflict(let card) = outcome { settle(card) }
            return outcome
        }
    }

    nonisolated static func outcome(for error: Error) -> ReviewDecideOutcome {
        switch error {
        case APIError.reviewConflict(let card): return .conflict(card)
        case APIError.noteRequired(let prompt): return .noteRequired(prompt)
        default: return .failed(error.localizedDescription)
        }
    }

    private func settle(_ card: ReviewCard) {
        open.removeAll { $0.id == card.id }
        recent.removeAll { $0.id == card.id }
        recent.insert(card, at: 0)
    }
}
