#!/usr/bin/env swift
// OB-52300: decode every fixtures/mobile-api.v1/*.json payload through Codable
// DTOs that mirror ARIA/Models production shapes. Fail non-zero on contract breakage.
//
// Run (the build Mac / macOS):
//   swift scripts/verify-contract-fixtures.swift
//   bash scripts/verify-contract-fixtures.sh
//
// Keep field names in lockstep with:
//   ARIA/Models/{Card,CommandAsk,InboxModels,ProactiveModels,HealthRecord,
//                LocationRecord,ActivityRecord}.swift
//   ARIA/Services/{APIClient,MusicKitService}.swift  (ForgeModel / MusicSyncResponse)
//   ARIA/Models/ContractFixtures.swift               (fixture catalog)
//
// Synthetic content only — no private data.

import Foundation

// MARK: - Errors

enum VerifyError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let s): return s
        }
    }
}

func fail(_ msg: String) -> Never {
    fputs("FAIL: \(msg)\n", stderr)
    exit(1)
}

// MARK: - DTO mirrors (production Codable field surface)

struct ReviewAction: Codable { let label: String; let style: String; let decision: String }
struct ReviewSelectOption: Codable { let label: String; let value: String; let description: String? }
struct ReviewSelect: Codable {
    let action: String
    let placeholder: String
    let min_values: Int
    let max_values: Int
    let options: [ReviewSelectOption]
}
struct ReviewCard: Codable {
    let id: String
    let kind: String
    let domain: String
    let title: String
    let body: String
    let posted_at: String?
    let expires_at: String?
    let status: String
    let selected_decision: String?
    let decided_at: String?
    let decided_by: String?
    let actions: [ReviewAction]
    let selects: [ReviewSelect]
    let reply_capture_actions: [String: String]
    let last_outcome: ReviewLastOutcome?   // contract 1.2.0 (OB-58965)
}
struct ReviewLastOutcome: Codable { let status: String; let decision: String; let reason: String; let at: String? }
struct ReviewCardsResponse: Codable { let contract_version: String; let generated_at: String; let cards: [ReviewCard] }
struct ReviewDecideResponse: Codable { let card: ReviewCard }
struct ReviewDecideConflict: Codable { let error: String; let card: ReviewCard }
struct ReviewDecideRejected: Codable { let error: String; let prompt: String? }

struct ForgeModel: Codable {
    let id: String
    let type: String?
    let provider: String?
    let status: String?
    let pickable: Bool?
    let deprecated_until: String?
    let retired_on: String?

    var isPickable: Bool {
        (pickable ?? false)
            && (status ?? "available") == "available"
            && deprecated_until == nil
            && retired_on == nil
            && (type == nil || type == "text" || type == "vlm")
    }
    var isLocal: Bool { provider == nil || provider?.isEmpty == true }
}

struct ForgeModelsResponse: Codable { let data: [ForgeModel] }

struct ChannelMessageDTO: Codable {
    let id: Int
    let channel_id: String
    let sender_id: String
    let message_type: String?
    let content: String
    let created_at: String
    var role: String { sender_id == "user" ? "user" : "assistant" }
}

struct ChannelHistoryResponse: Codable {
    let messages: [ChannelMessageDTO]
    let has_more: Bool?
}

struct HealthSyncResponse: Codable {
    let synced: Int
    let inserted: Int?
    let conflicted: Int?
    let errored: Int?
    let total: Int?
}

struct LocationSyncResponse: Codable { let saved: Bool }
struct VisitSyncResponse: Codable { let saved: Int }
struct ActivitySyncResponse: Codable { let saved: Bool }
struct ActivityBulkSyncResponse: Codable {
    let saved: Int
    let total: Int
    let valid: Int
}
struct IngestAckMirror: Codable {
    struct Rejection: Codable { let id: String?; let error: String }
    let accepted: [String]
    let duplicate: [String]
    let rejected: [Rejection]
}
struct MusicSyncResponse: Codable {
    let synced: Int
    let playlists_synced: Int?
}

struct EmptyOk: Codable {
    // device-token returns {ok:true}; empty {} also fine
    let ok: Bool?
}

struct CommandToolCall: Codable {
    let tool: String
    let ok: Bool
    let result: String?
}

struct CommandAskResponse: Codable {
    let answer: String
    let toolCalls: [CommandToolCall]
    let readToolCount: Int
    let steps: Int
    let truncated: Bool
}

struct InboxItem: Codable {
    let id: String
    let title: String
    let body: String
    let category: String
    let urgency: String
    let source: String
    let source_id: String?
    let insight_id: String?
    let conversation_id: String?
    let is_read: Bool
    let read_at: String?
    let feedback_rating: Int?
    let feedback_comment: String?
    let created_at: String
}

struct InboxListResponse: Codable {
    let items: [InboxItem]
    let total: Int
    let unreadCount: Int
}

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        }
    }
}

struct PushPreferencesDTO: Codable {
    var notifications: Bool
    var reports: Bool
    var urgency_filter: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = (try? c.decode(Bool.self, forKey: .notifications)) ?? true
        reports = (try? c.decode(Bool.self, forKey: .reports)) ?? false
        urgency_filter = (try? c.decode(String.self, forKey: .urgency_filter)) ?? "all"
    }
}

struct NotificationMethodDTO: Codable {
    let id: String
    let channel: String
    let label: String
    let config: [String: JSONValue]?
    let is_enabled: Bool
    let push_preferences: PushPreferencesDTO?
    let created_at: String
    let updated_at: String
}

struct NotificationMethodsResponse: Codable { let methods: [NotificationMethodDTO] }

struct DevicePreferenceDTO: Codable {
    let id: String
    let label: String
    let is_enabled: Bool
    let push_preferences: PushPreferencesDTO
}

struct DevicePreferencesResponse: Codable { let devices: [DevicePreferenceDTO] }

struct ProactiveSettingsDTO: Codable {
    let risk_level: String
    let urgent_delivery_methods: [String]
    let standard_delivery_methods: [String]
    let digest_schedule: DigestSchedule
    let confidence_threshold: Double
    let gmail_check_interval_seconds: Int?
    let fast_track_patterns: FastTrackPatternsDTO?

    struct DigestSchedule: Codable {
        let morning: String
        let evening: String
    }
}

struct FastTrackPatternsDTO: Codable {
    var auto_adapt_enabled: Bool
    var universal_patterns: [String]
    var adaptive_patterns: [AdaptivePatternEntry]
    var context_summary: String
    var last_regenerated_at: String?

    struct AdaptivePatternEntry: Codable {
        let pattern: String
        let reason: String
    }
}

struct ProactiveSettingsResponse: Codable { let settings: ProactiveSettingsDTO }

struct InsightEvidence: Codable {
    let snapshots: [EvidenceSnapshot]?
    let triggered_at: String?
    struct EvidenceSnapshot: Codable {
        let source: String
        let summary: String
    }
}

struct ProactiveInsightDTO: Codable {
    let id: String
    let title: String
    let body: String
    let reasoning: String?
    let evidence: InsightEvidence?
    let category: String
    let urgency: String
    let confidence: Double
    let status: String
    let feedback_rating: Int?
    let feedback_comment: String?
    let created_at: String
    let delivered_at: String?
    let expires_at: String?
}

struct InsightsResponse: Codable { let insights: [ProactiveInsightDTO] }

// MARK: - Mobile bootstrap (OB-52301)

struct MobileBootstrap: Codable {
    let contract_version: String
    let server_time: String
    let supported_features: SupportedFeatures
    let push: PushCapability
    let data_source_freshness_thresholds: FreshnessThresholds
    let app_version: AppVersionHints
    let route_flags: [String: String]

    struct SupportedFeatures: Codable {
        let chat: Bool
        let command_ask: Bool
        let health_sync: Bool
        let location_sync: Bool
        let activity_sync: Bool
        let music_sync: Bool
        let push: Bool
        let inbox: Bool
        let proactive: Bool
        let notifications_settings: Bool
        let review_cards: Bool?
    }
    struct PushCapability: Codable { let device_token_registration: Bool }
    struct FreshnessThresholds: Codable {
        let health_hours: Int
        let location_hours: Int
        let activity_hours: Int
        let music_hours: Int
    }
    struct AppVersionHints: Codable {
        let minimum: String?
        let recommended: String?
    }
}

// MARK: - Mobile freshness (OB-52302)

struct MobileFreshness: Codable {
    let contract_version: String
    let server_time: String
    let sources: [Source]
    let summary: Summary
    let platform: Platform

    struct Source: Codable {
        let source_key: String
        let app_key: String
        let display_label: String
        let kind: String
        let status: String
        let last_seen_at: String?
        let age_bucket: String
        let expected_cadence_hours: Double?
        let failure_class: String?
        let user_facing_state: String
    }
    struct Summary: Codable {
        let fresh: Int
        let stale: Int
        let error: Int
        let empty: Int
        let unknown: Int
        let disabled: Int
        let overall: String
    }
    struct Platform: Codable {
        let bridge_health: String
        let worker_queue: WorkerQueue
        struct WorkerQueue: Codable {
            let pending: Int?
            let status: String
        }
    }
}

// MARK: - Decode helpers

let decoder = JSONDecoder()

func load(_ path: URL) throws -> Data {
    try Data(contentsOf: path)
}

func decode<T: Decodable>(_ type: T.Type, from data: Data, label: String) throws -> T {
    do {
        return try decoder.decode(T.self, from: data)
    } catch {
        throw VerifyError.message("\(label): decode failed — \(error)")
    }
}


// Script-local DTO for the one-big-thing payload (OB-66557); the app
// decodes through MobileOneBigThing in ARIA/Models/OneBigThing.swift.
struct OneBigThingScriptDTO: Decodable {
    struct Input: Decodable { let status: String; let value: Double?; let score: Int? }
    struct Readiness: Decodable { let score: Int; let confidence: String; let inputs: [String: Input] }
    struct Contributor: Decodable { let status: String; let score: Int? }
    struct Stress: Decodable { let index: Int; let window_days: Int; let contributors: [String: Contributor] }
    struct BodyAge: Decodable { let delta_index: Double; let direction: String }
    struct Seed: Decodable { let headline_facts: [String]; let fallback_paragraph: String }
    let contract_version: String
    let for_date: String
    let readiness: Readiness
    let cumulative_stress: Stress
    let body_age_index: BodyAge
    let brief_seed: Seed
    let data_notes: [String]
}

// MARK: - Main

let repoRoot: URL = {
    // Prefer CWD (script invoked from repo root); fall back to script-relative.
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidate = cwd.appendingPathComponent("fixtures/mobile-api.v1")
    if FileManager.default.fileExists(atPath: candidate.path) {
        return cwd
    }
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
        .standardizedFileURL
        .deletingLastPathComponent() // scripts/
        .deletingLastPathComponent() // repo root
    return scriptDir
}()

// Script-local DTO for the photo-intelligence ingest ack (OB-66559); the
// app decodes through PhotoIntelligenceResponse in ARIA/Models/PhotoIntelligence.swift.
struct PhotoTermsAckDTO: Decodable {
    let received_terms: Int
    let inserted: Int
    let duplicates: Int
}

struct PhotoIntelligenceAckDTO: Decodable {
    let received: Int
    let inserted: Int
    let duplicates: Int
}

// Script-local DTO for the photo-intelligence enrich ack (OB-68202); the
// app decodes through PhotoIntelligenceEnrichResponse in ARIA/Models/PhotoIntelligence.swift.
struct PhotoIntelligenceEnrichAckDTO: Decodable {
    let received: Int
    let updated: Int
    let not_found: Int
}

// Script-local DTOs for the Life Replay payloads (OB-66560); the app
// decodes through ReplayDayPack / ReplayAskResponse in ARIA/Models/Replay.swift.
enum ScriptFieldValue: Decodable {
    case string(String), number(Double), bool(Bool), null, array([ScriptFieldValue]), object([String: ScriptFieldValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([ScriptFieldValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: ScriptFieldValue].self)) }
    }
}
struct ReplayItemScriptDTO: Decodable {
    let id: String; let family: String; let source: String; let timestamp: String; let summary: String
    let fields: [String: ScriptFieldValue]
}
struct ReplayDayScriptDTO: Decodable {
    struct Family: Decodable { let count: Int; let truncated: Bool; let items: [ReplayItemScriptDTO] }
    let contract_version: String; let date: String; let item_count: Int
    let families: [String: Family]; let counts: [String: Int]; let data_notes: [String]
}
struct ReplayAskScriptDTO: Decodable {
    struct Pack: Decodable { let item_count: Int; let truncated: Bool }
    let contract_version: String; let narrative: String
    let citations: [ReplayItemScriptDTO]; let unresolved_citations: [String]; let pack: Pack
}

let fixturesDir = repoRoot.appendingPathComponent("fixtures/mobile-api.v1")
guard FileManager.default.fileExists(atPath: fixturesDir.path) else {
    fail("fixtures dir missing: \(fixturesDir.path) — run from aria-ios repo root")
}

let expected: [(String, (Data) throws -> Void)] = [
    ("mobile-one-big-thing", { data in
        let r = try decode(OneBigThingScriptDTO.self, from: data, label: "mobile-one-big-thing")
        guard r.contract_version == "1.3.0", r.readiness.score == 52, r.readiness.inputs.count == 6 else { throw VerifyError.message("mobile-one-big-thing: readiness") }
        guard r.cumulative_stress.contributors.count == 5, r.body_age_index.delta_index == -0.1 else { throw VerifyError.message("mobile-one-big-thing: composites") }
    }),
    ("mobile-photo-intelligence", { data in
        let r = try decode(PhotoIntelligenceAckDTO.self, from: data, label: "mobile-photo-intelligence")
        guard r.received == 2, r.inserted == 2, r.duplicates == 0 else { throw VerifyError.message("mobile-photo-intelligence: ack counts") }
    }),
    ("mobile-photo-intelligence-enrich", { data in
        let r = try decode(PhotoIntelligenceEnrichAckDTO.self, from: data, label: "mobile-photo-intelligence-enrich")
        guard r.received == 3, r.updated == 2, r.not_found == 1 else { throw VerifyError.message("mobile-photo-intelligence-enrich: ack counts") }
    }),
    ("mobile-photo-terms", { data in
        let r = try decode(PhotoTermsAckDTO.self, from: data, label: "mobile-photo-terms")
        guard r.received_terms == 10, r.inserted == 9, r.duplicates == 1 else { throw VerifyError.message("mobile-photo-terms: ack counts") }
    }),
    ("mobile-replay-day", { data in
        let r = try decode(ReplayDayScriptDTO.self, from: data, label: "mobile-replay-day")
        guard r.contract_version == "1.3.0", r.item_count == 3, r.families["visits"]?.items.first?.id == "visit:11111111-2222-3333-4444-555555555555" else { throw VerifyError.message("mobile-replay-day: pack") }
        guard case .number(7.5)? = r.families["health"]?.items.first?.fields["duration_hours"] else { throw VerifyError.message("mobile-replay-day: health fields") }
    }),
    ("mobile-replay-ask", { data in
        let r = try decode(ReplayAskScriptDTO.self, from: data, label: "mobile-replay-ask")
        guard r.citations.count == 2, r.unresolved_citations.isEmpty, r.pack.item_count == 3 else { throw VerifyError.message("mobile-replay-ask: citations") }
        guard r.narrative.contains("[cite:sleep:2026-01-12]") else { throw VerifyError.message("mobile-replay-ask: markers") }
    }),
    ("review-cards-open", { data in
        let r = try decode(ReviewCardsResponse.self, from: data, label: "review-cards-open")
        guard r.contract_version == "1.3.0", r.cards.count == 2 else { throw VerifyError.message("review-cards-open: expected 2 cards @1.3.0") }
        guard r.cards[0].reply_capture_actions["link_person"] != nil else { throw VerifyError.message("review-cards-open: reply capture") }
        guard r.cards[0].last_outcome?.reason.isEmpty == false, r.cards[1].last_outcome == nil else { throw VerifyError.message("review-cards-open: last_outcome (1.2.0)") }
        guard r.cards[1].selects.first?.options.first?.value == "p-1" else { throw VerifyError.message("review-cards-open: select") }
    }),
    ("review-cards-recent", { data in
        let r = try decode(ReviewCardsResponse.self, from: data, label: "review-cards-recent")
        guard r.cards.count == 1, r.cards[0].status == "decided" else { throw VerifyError.message("review-cards-recent") }
    }),
    ("review-card-decide-ok", { data in
        let r = try decode(ReviewDecideResponse.self, from: data, label: "review-card-decide-ok")
        guard r.card.status == "decided" else { throw VerifyError.message("review-card-decide-ok") }
    }),
    ("review-card-decide-conflict", { data in
        let r = try decode(ReviewDecideConflict.self, from: data, label: "review-card-decide-conflict")
        guard r.error == "already_decided" else { throw VerifyError.message("review-card-decide-conflict") }
    }),
    ("review-card-decide-note-required", { data in
        let r = try decode(ReviewDecideRejected.self, from: data, label: "review-card-decide-note-required")
        guard r.error == "note_required", r.prompt != nil else { throw VerifyError.message("review-card-decide-note-required") }
    }),
    ("forge-models", { data in
        let r = try decode(ForgeModelsResponse.self, from: data, label: "forge-models")
        let pickable = r.data.filter { $0.isPickable }
        guard pickable.count == 2 else { throw VerifyError.message("forge-models: expected 2 pickable, got \(pickable.count)") }
        guard pickable.contains(where: { $0.isLocal }) && pickable.contains(where: { !$0.isLocal }) else {
            throw VerifyError.message("forge-models: need local+cloud")
        }
    }),
    ("channel-history", { data in
        let r = try decode(ChannelHistoryResponse.self, from: data, label: "channel-history")
        guard r.messages.count == 2 else { throw VerifyError.message("channel-history count") }
        guard r.messages[0].role == "user", r.messages[1].role == "assistant" else {
            throw VerifyError.message("channel-history roles")
        }
    }),
    ("channel-history-empty", { data in
        let r = try decode(ChannelHistoryResponse.self, from: data, label: "channel-history-empty")
        guard r.messages.isEmpty else { throw VerifyError.message("channel-history-empty") }
    }),
    ("health-sync", { data in
        let r = try decode(HealthSyncResponse.self, from: data, label: "health-sync")
        guard r.synced == 3 else { throw VerifyError.message("health-sync.synced") }
    }),
    ("location-sync", { data in
        let r = try decode(LocationSyncResponse.self, from: data, label: "location-sync")
        guard r.saved else { throw VerifyError.message("location-sync") }
    }),
    ("visit-sync", { data in
        let r = try decode(VisitSyncResponse.self, from: data, label: "visit-sync")
        guard r.saved == 2 else { throw VerifyError.message("visit-sync") }
    }),
    ("activity-sync", { data in
        let r = try decode(ActivitySyncResponse.self, from: data, label: "activity-sync")
        guard r.saved else { throw VerifyError.message("activity-sync") }
    }),
    ("activity-bulk-sync", { data in
        let r = try decode(ActivityBulkSyncResponse.self, from: data, label: "activity-bulk-sync")
        guard r.saved == 4, r.total == 4 else { throw VerifyError.message("activity-bulk-sync") }
    }),
    ("music-sync", { data in
        let r = try decode(MusicSyncResponse.self, from: data, label: "music-sync")
        guard r.synced == 5 else { throw VerifyError.message("music-sync") }
    }),
    ("device-events-ack", { data in
        let r = try decode(IngestAckMirror.self, from: data, label: "device-events-ack")
        guard r.accepted.count == 1, r.duplicate.count == 1, r.rejected.first?.id == nil else { throw VerifyError.message("device-events-ack") }
    }),
    ("health-files-ack", { data in
        let r = try decode(IngestAckMirror.self, from: data, label: "health-files-ack")
        guard r.accepted.first?.hasPrefix("hk:") == true else { throw VerifyError.message("health-files-ack") }
    }),
    ("device-token-ok", { data in
        _ = try decode(EmptyOk.self, from: data, label: "device-token-ok")
    }),
    ("command-ask", { data in
        let r = try decode(CommandAskResponse.self, from: data, label: "command-ask")
        guard !r.answer.isEmpty, r.toolCalls.count == 1, r.readToolCount == 1 else {
            throw VerifyError.message("command-ask fields")
        }
    }),
    ("inbox-list", { data in
        let r = try decode(InboxListResponse.self, from: data, label: "inbox-list")
        guard r.items.count == 1, r.unreadCount == 1, r.items[0].is_read == false else {
            throw VerifyError.message("inbox-list")
        }
    }),
    ("inbox-list-empty", { data in
        let r = try decode(InboxListResponse.self, from: data, label: "inbox-list-empty")
        guard r.items.isEmpty, r.total == 0 else { throw VerifyError.message("inbox-list-empty") }
    }),
    ("notification-methods", { data in
        let r = try decode(NotificationMethodsResponse.self, from: data, label: "notification-methods")
        guard r.methods.count == 1, r.methods[0].channel == "push" else {
            throw VerifyError.message("notification-methods")
        }
    }),
    ("device-preferences", { data in
        let r = try decode(DevicePreferencesResponse.self, from: data, label: "device-preferences")
        guard r.devices.count == 1, r.devices[0].push_preferences.notifications else {
            throw VerifyError.message("device-preferences")
        }
    }),
    ("proactive-settings", { data in
        let r = try decode(ProactiveSettingsResponse.self, from: data, label: "proactive-settings")
        guard r.settings.risk_level == "balanced" else { throw VerifyError.message("proactive-settings") }
    }),
    ("proactive-insights", { data in
        let r = try decode(InsightsResponse.self, from: data, label: "proactive-insights")
        guard r.insights.count == 1, r.insights[0].id == "insight-synthetic-1" else {
            throw VerifyError.message("proactive-insights")
        }
    }),
    ("proactive-insights-empty", { data in
        let r = try decode(InsightsResponse.self, from: data, label: "proactive-insights-empty")
        guard r.insights.isEmpty else { throw VerifyError.message("proactive-insights-empty") }
    }),
    ("mobile-bootstrap-ready", { data in
        let r = try decode(MobileBootstrap.self, from: data, label: "mobile-bootstrap-ready")
        guard r.contract_version == "1.3.0", r.supported_features.review_cards == true else {
            throw VerifyError.message("mobile-bootstrap-ready")
        }
    }),
    ("mobile-bootstrap-minimal", { data in
        let r = try decode(MobileBootstrap.self, from: data, label: "mobile-bootstrap-minimal")
        guard r.supported_features.review_cards == false else { throw VerifyError.message("mobile-bootstrap-minimal") }
    }),
    ("mobile-freshness-mixed", { data in
        let r = try decode(MobileFreshness.self, from: data, label: "mobile-freshness-mixed")
        guard r.contract_version == "1.0.0",
              r.sources.count == 7,
              r.summary.overall == "error",
              r.sources.contains(where: { $0.app_key == "health" && $0.status == "fresh" }),
              r.sources.contains(where: { $0.app_key == "location" && $0.status == "stale" }),
              r.sources.contains(where: { $0.app_key == "motion" && $0.status == "error" }),
              r.sources.contains(where: { $0.app_key == "music" && $0.status == "empty" }),
              r.platform.worker_queue.status == "ok" else {
            throw VerifyError.message("mobile-freshness-mixed")
        }
    }),
]

var passed = 0
for (name, check) in expected {
    let path = fixturesDir.appendingPathComponent("\(name).json")
    guard FileManager.default.fileExists(atPath: path.path) else {
        fail("missing fixture file: \(name).json")
    }
    do {
        let data = try load(path)
        // Reject non-JSON
        _ = try JSONSerialization.jsonObject(with: data)
        try check(data)
        print("  ok  \(name)")
        passed += 1
    } catch {
        fail("\(name): \(error)")
    }
}

// Ensure no untracked fixture files without a decoder (except manifest).
let listed = try! FileManager.default.contentsOfDirectory(atPath: fixturesDir.path)
    .filter { $0.hasSuffix(".json") && $0 != "manifest.json" }
    .sorted()
let expectedNames = Set(expected.map { $0.0 + ".json" })
for f in listed where !expectedNames.contains(f) {
    fail("fixture \(f) has no decoder case — add it to verify-contract-fixtures.swift")
}

print("PASS: decoded \(passed)/\(expected.count) fixtures (contract mobile-api.v1)")
exit(0)
