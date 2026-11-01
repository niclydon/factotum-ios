import Foundation

// MARK: - Proactive Settings

struct ProactiveSettingsResponse: Codable, Sendable {
    let settings: ProactiveSettingsDTO
}

struct ProactiveSettingsDTO: Codable, Sendable {
    let risk_level: String
    let urgent_delivery_methods: [String]
    let standard_delivery_methods: [String]
    let digest_schedule: DigestSchedule
    let confidence_threshold: Double
    let gmail_check_interval_seconds: Int?
    let fast_track_patterns: FastTrackPatternsDTO?

    struct DigestSchedule: Codable, Sendable {
        let morning: String
        let evening: String
    }
}

// MARK: - Fast-Track Patterns

struct FastTrackPatternsDTO: Codable, Sendable {
    var auto_adapt_enabled: Bool
    var universal_patterns: [String]
    var adaptive_patterns: [AdaptivePatternEntry]
    var context_summary: String
    var last_regenerated_at: String?

    struct AdaptivePatternEntry: Codable, Sendable, Identifiable {
        let pattern: String
        let reason: String
        var id: String { pattern }
    }

    static let `default` = FastTrackPatternsDTO(
        auto_adapt_enabled: true,
        universal_patterns: ["\\b911\\b", "\\bSOS\\b", "\\bemergency\\b", "\\bfall\\b", "\\bfell\\b", "\\baccident\\b", "\\bcrash\\b"],
        adaptive_patterns: [],
        context_summary: "",
        last_regenerated_at: nil
    )
}

// MARK: - Notification Methods

struct NotificationMethodsResponse: Codable, Sendable {
    let methods: [NotificationMethodDTO]
}

/// Flexible JSON value for decoding heterogeneous JSONB columns.
enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if container.decodeNil() { self = .null }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

struct PushPreferencesDTO: Codable, Sendable {
    var notifications: Bool
    var reports: Bool
    var urgency_filter: String  // "all" or "urgent"

    static let `default` = PushPreferencesDTO(notifications: true, reports: false, urgency_filter: "all")

    // Custom decoder so that an empty {} from older DB rows decodes as the default
    // rather than throwing a DecodingError that would crash the whole dashboard load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = (try? c.decode(Bool.self, forKey: .notifications)) ?? true
        reports = (try? c.decode(Bool.self, forKey: .reports)) ?? false
        urgency_filter = (try? c.decode(String.self, forKey: .urgency_filter)) ?? "all"
    }

    init(notifications: Bool, reports: Bool, urgency_filter: String) {
        self.notifications = notifications
        self.reports = reports
        self.urgency_filter = urgency_filter
    }
}

struct NotificationMethodDTO: Codable, Sendable, Identifiable {
    let id: String
    let channel: String
    let label: String
    let config: [String: JSONValue]?
    let is_enabled: Bool
    let push_preferences: PushPreferencesDTO?
    let created_at: String
    let updated_at: String

    var displayName: String {
        "\(label) (\(channel))"
    }
}

struct DevicePreferencesResponse: Codable, Sendable {
    let devices: [DevicePreferenceDTO]
}

struct DevicePreferenceDTO: Codable, Sendable, Identifiable {
    let id: String
    let label: String
    let is_enabled: Bool
    let push_preferences: PushPreferencesDTO
}

struct UpdateDevicePreferencesResponse: Codable, Sendable {
    let device: DevicePreferenceDTO
}

// MARK: - Proactive Insights

struct InsightsResponse: Codable, Sendable {
    let insights: [ProactiveInsightDTO]
}

struct ProactiveInsightDTO: Codable, Sendable, Identifiable {
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

    var isUrgent: Bool { urgency == "urgent" }

    var categoryLabel: String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: created_at) else { return created_at }
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Insight Evidence

struct InsightEvidence: Codable, Sendable {
    let snapshots: [EvidenceSnapshot]?
    let triggered_at: String?

    struct EvidenceSnapshot: Codable, Sendable {
        let source: String
        let summary: String
    }
}

// MARK: - Patterns

struct PatternsResponse: Codable, Sendable {
    let patterns: [AnticipationPatternDTO]
}

struct AnticipationPatternDTO: Codable, Sendable, Identifiable {
    let id: String
    let pattern_type: String
    let description: String
    let confidence: Double
    let observation_count: Int
    let last_observed_at: String
    let promoted_to_memory: Bool
    let memory_key: String?
    let is_active: Bool
}

// MARK: - PIE Debug Dashboard

struct PIEDebugResponse: Codable, Sendable {
    let pipeline_status: PipelineStatus
    let recent_snapshots: [ContextSnapshotDTO]
    let recent_insights: [DebugInsightDTO]
    let gate_stats: GateStats
    let recent_jobs: [PIEJobDTO]
    let fast_track: FastTrackStatus
    let watermarks: [WatermarkDTO]

    struct PipelineStatus: Codable, Sendable {
        let enabled: Bool
        let risk_level: String
        let confidence_threshold: Double
        let last_accumulation_at: String?
        let last_significance_at: String?
        let last_anticipation_at: String?
    }

    struct GateStats: Codable, Sendable {
        let snapshots_by_source: [String: Int]
        let classification_breakdown: [String: Int]
        let insights_generated_24h: Int
        let insights_delivered_24h: Int
        let fast_tracked_24h: Int
    }

    struct FastTrackStatus: Codable, Sendable {
        let universal_patterns: [String]
        let adaptive_patterns: [String]
        let context_summary: String?
        let last_regenerated_at: String?
    }
}

struct ContextSnapshotDTO: Codable, Sendable, Identifiable {
    let id: String
    let source: String
    let change_summary: String
    let significance: String
    let fast_tracked: Bool
    let analyzed: Bool
    let created_at: String

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: created_at) else { return created_at }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    var significanceColor: String {
        switch significance {
        case "urgent": return "red"
        case "significant": return "orange"
        case "notable": return "blue"
        case "insignificant": return "gray"
        default: return "gray"
        }
    }
}

struct DebugInsightDTO: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let reasoning: String?
    let category: String
    let urgency: String
    let confidence: Double
    let status: String
    let delivery_methods: [String]?
    let feedback_rating: Int?
    let source_snapshots: InsightEvidence?
    let created_at: String
    let delivered_at: String?

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: created_at) else { return created_at }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

struct PIEJobDTO: Codable, Sendable, Identifiable {
    let id: String
    let type: String
    let status: String
    let created_at: String
    let completed_at: String?
    let result: PIEJobResult?

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: created_at) else { return created_at }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    var gateLabel: String {
        switch type {
        case "context-accumulate": return "Gate 1"
        case "significance-check": return "Gate 2"
        case "anticipation-analyze": return "Gate 3"
        case "insight-deliver": return "Gate 4"
        default: return type
        }
    }

    var statusColor: String {
        switch status {
        case "completed": return "green"
        case "failed": return "red"
        case "processing": return "yellow"
        default: return "gray"
        }
    }
}

struct PIEJobResult: Codable, Sendable {
    let message: String?
    let error: String?

    init(from decoder: Decoder) throws {
        // Handle varied result shapes gracefully
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            message = try? container.decode(String.self, forKey: .message)
            error = try? container.decode(String.self, forKey: .error)
        } else if let str = try? decoder.singleValueContainer().decode(String.self) {
            message = str
            error = nil
        } else {
            message = nil
            error = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case message, error
    }
}

struct WatermarkDTO: Codable, Sendable, Identifiable {
    let source: String
    let last_checked_at: String
    let last_change_detected_at: String?

    var id: String { source }

    var relativeChecked: String {
        guard let date = ISO8601DateFormatter().date(from: last_checked_at) else { return last_checked_at }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    var relativeChanged: String? {
        guard let ts = last_change_detected_at,
              let date = ISO8601DateFormatter().date(from: ts) else { return nil }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
