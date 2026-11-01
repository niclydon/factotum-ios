// ARIA/Models/ReviewContract.swift
import Foundation

/// Pins the client's interpretation of the review-card contract (spec §2): domain grouping/order,
/// note requirements, and the decide state machine. Runs at DEBUG launch like the other contracts.
enum ReviewContract {
    #if DEBUG
    static func runSelfCheck() {
        do {
            let open = try JSONDecoder().decode(ReviewCardsResponse.self, from: Data(ContractFixtures.reviewCardsOpen.utf8)).cards
            // Grouping: identity before knowledge_graph; unknown domain last.
            let groups = ReviewStore.group(open)
            precondition(groups.map(\.domain) == ["identity", "knowledge_graph"], "review grouping order")
            // Note requirement is per action, read from the card, never hard-coded per kind.
            precondition(open[0].requiresNote(for: "link_person") && !open[0].requiresNote(for: "dismissed"), "reply capture")
            // Decide state machine.
            precondition(ReviewStore.outcome(for: APIError.reviewConflict(open[0])) == .conflict(open[0]), "409 → conflict")
            precondition(ReviewStore.outcome(for: APIError.noteRequired(prompt: "p")) == .noteRequired("p"), "400 → noteRequired")
            precondition(ReviewStore.outcome(for: APIError.unauthorized) == .failed(APIError.unauthorized.localizedDescription), "other → failed")
            Logger.shared.log("contract", "ReviewContract self-check OK")
        } catch {
            preconditionFailure("ReviewContract fixture decode failed: \(error)")
        }
    }
    #endif
}
