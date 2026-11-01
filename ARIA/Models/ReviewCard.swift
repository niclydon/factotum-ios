// ARIA/Models/ReviewCard.swift
import Foundation

/// One operator review card from Nexus's generic card bus (`review_card_queue`), served by
/// `GET /api/mobile/review-cards`. The phone MIRRORS Discord: same rows, same decision tokens.
/// Spec: docs/superpowers/specs/2026-09-06-review-tab-and-today-design.md §1–2.
struct ReviewCard: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let kind: String
    let domain: String
    let title: String
    let body: String
    let postedAt: String?
    let expiresAt: String?
    var status: String
    var selectedDecision: String?
    var decidedAt: String?
    var decidedBy: String?
    let actions: [ReviewAction]
    let selects: [ReviewSelect]
    let replyCaptureActions: [String: String]
    /// Contract 1.2.0 (OB-58965): why the last recorded decision was not applied; nil unless the card was reopened.
    let lastOutcome: ReviewLastOutcome?

    enum CodingKeys: String, CodingKey {
        case id, kind, domain, title, body, status, actions, selects
        case postedAt = "posted_at"
        case expiresAt = "expires_at"
        case selectedDecision = "selected_decision"
        case decidedAt = "decided_at"
        case decidedBy = "decided_by"
        case replyCaptureActions = "reply_capture_actions"
        case lastOutcome = "last_outcome"
    }

    /// Defensive decode: arrays/maps default when absent so one odd card never drops the list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        domain = try c.decode(String.self, forKey: .domain)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? Self.humanise(kind)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        postedAt = try c.decodeIfPresent(String.self, forKey: .postedAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "posted"
        selectedDecision = try c.decodeIfPresent(String.self, forKey: .selectedDecision)
        decidedAt = try c.decodeIfPresent(String.self, forKey: .decidedAt)
        decidedBy = try c.decodeIfPresent(String.self, forKey: .decidedBy)
        actions = try c.decodeIfPresent([ReviewAction].self, forKey: .actions) ?? []
        selects = try c.decodeIfPresent([ReviewSelect].self, forKey: .selects) ?? []
        replyCaptureActions = try c.decodeIfPresent([String: String].self, forKey: .replyCaptureActions) ?? [:]
        lastOutcome = try c.decodeIfPresent(ReviewLastOutcome.self, forKey: .lastOutcome)
    }

    var isOpen: Bool { status == "posted" }
    var isDecided: Bool { status == "decided" || status == "archived" }
    var decidedOnThisPhone: Bool { decidedBy?.hasPrefix("ios:") == true }

    /// Reply-capture actions need a note (the Discord flow asks for a reply).
    func requiresNote(for decision: String) -> Bool { replyCaptureActions[decision] != nil }
    func prompt(for decision: String) -> String? { replyCaptureActions[decision] }

    /// Fixed Life-domain display order (spec §3). Unknown domains sort last.
    static let domainOrder = ["identity", "knowledge_graph", "knowledge", "memoir", "habit", "relationship", "timeline", "signal"]
    var domainRank: Int { Self.domainOrder.firstIndex(of: domain) ?? Self.domainOrder.count }

    static func humanise(_ key: String) -> String {
        let s = key.replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    static func domainTitle(_ domain: String) -> String {
        switch domain {
        case "knowledge_graph": return "Knowledge graph"
        default: return humanise(domain)
        }
    }
}

/// Contract 1.2.0 (OB-58965): set by Nexus when a recorded decision could not be applied (e.g. "Link to a
/// person" found no match). The card is reopened with the same buttons; show `reason` so the operator can
/// answer with a better name or an id.
struct ReviewLastOutcome: Codable, Sendable, Hashable {
    let status: String
    let decision: String
    let reason: String
    let at: String?
}

struct ReviewAction: Codable, Sendable, Hashable {
    enum Style: String, Codable, Sendable { case primary, success, danger, secondary }
    let label: String
    let style: Style
    let decision: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        decision = try c.decode(String.self, forKey: .decision)
        style = (try? c.decode(Style.self, forKey: .style)) ?? .secondary
    }
    init(label: String, style: Style, decision: String) { self.label = label; self.style = style; self.decision = decision }
}

struct ReviewSelectOption: Codable, Sendable, Hashable, Identifiable {
    let label: String
    let value: String
    let description: String?
    var id: String { value }
}

struct ReviewSelect: Codable, Sendable, Hashable {
    let action: String
    let placeholder: String
    let minValues: Int
    let maxValues: Int
    let options: [ReviewSelectOption]
    enum CodingKeys: String, CodingKey {
        case action, placeholder, options
        case minValues = "min_values"
        case maxValues = "max_values"
    }
}

/// `GET /api/mobile/review-cards` envelope.
struct ReviewCardsResponse: Codable, Sendable {
    let contractVersion: String
    let generatedAt: String
    let cards: [ReviewCard]
    enum CodingKeys: String, CodingKey {
        case cards
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
    }
}

/// `POST /api/mobile/review-cards/:id/decide` 200 body; the 409 body is `ReviewDecideConflict`.
struct ReviewDecideResponse: Codable, Sendable { let card: ReviewCard }
struct ReviewDecideConflict: Codable, Sendable { let error: String; let card: ReviewCard }
struct ReviewDecideRejected: Codable, Sendable { let error: String; let prompt: String? }

enum ReviewListStatus: String, Sendable { case open, recent }
