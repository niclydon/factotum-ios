import Foundation
import SwiftUI

// MARK: - Event Log

struct EventLogResponse: Codable, Sendable {
    let events: [EventLogEntry]
}

struct EventLogEntry: Codable, Sendable, Identifiable {
    let id: String
    let action: String
    let component: String
    let category: String
    let status: String
    let metadata: [String: JSONValue]?
    let created_at: String

    enum CodingKeys: String, CodingKey {
        case id, action, component, category, status, metadata, created_at
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

    var categoryColor: Color {
        switch category {
        case "direct_response": .cyan
        case "background": .purple
        case "interaction": .green
        case "self_maintenance": .orange
        case "integration": .blue
        case "system": .red
        default: .gray
        }
    }

    var statusColor: Color {
        status == "success" ? ARIATheme.success : ARIATheme.error
    }
}

// MARK: - iMessage Queue

struct IMessageHistoryResponse: Codable, Sendable {
    let messages: [IMessageEntry]
}

struct IMessageEntry: Codable, Sendable, Identifiable {
    let id: String
    let recipient: String
    let message: String
    let status: String
    let error: String?
    let created_at: String
    let claimed_at: String?
    let sent_at: String?

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

    var statusColor: Color {
        switch status {
        case "pending": .yellow
        case "claimed": .blue
        case "sent": .green
        case "failed": .red
        default: .gray
        }
    }

    var statusLabel: String {
        status.capitalized
    }

    var formattedDate: String {
        guard let date = ISO8601DateFormatter().date(from: created_at) else { return created_at }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: date)
    }
}

// MARK: - Custom Prompt

struct CustomPromptResponse: Codable, Sendable {
    let prompt: String
}

// MARK: - Settings (generic key-value)

struct SettingResponse: Codable, Sendable {
    let setting: SettingEntry?
}

struct SettingEntry: Codable, Sendable {
    let key: String
    let value: String
}

// MARK: - Skills

struct SkillsResponse: Codable, Sendable {
    let skills: [Skill]
    let budget: SkillBudget
}

struct Skill: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let source_url: String
    let content_length: Int
    let active: Bool
    let created_at: String
    let updated_at: String
}

struct SkillBudget: Codable, Sendable {
    let used: Int
    let cap: Int
    let remaining: Int
}

struct SkillImportResponse: Codable, Sendable {
    let skill: SkillImportResult?
    let error: String?

    struct SkillImportResult: Codable, Sendable {
        let id: String?
        let name: String?
    }
}

struct SkillToggleResponse: Codable, Sendable {
    let skill: String?
    let active: Bool?
    let error: String?
}

// MARK: - ARIA Photos

struct AriaPhotosResponse: Codable, Sendable {
    let photos: [AriaPhoto]
}

struct AriaPhoto: Codable, Sendable, Identifiable {
    let id: String
    let image_data: String
    let mime_type: String
    let label: String?
    let created_at: String
}

// MARK: - Social Dashboard

struct SocialDashboardResponse: Codable, Sendable {
    let identity: SocialIdentity?
    let stats: [SocialStat]
    let dailyActivity: [DailyActivity]
    let topConnections: [SocialConnection]
    let topSubmolts: [SubmoltStat]
    let recentInteractions: [SocialInteraction]
    let recentReflections: [SocialReflection]
    let metrics: SocialMetrics

    struct SocialIdentity: Codable, Sendable {
        let id: String
        let network: String
        let agent_name: String
        let agent_description: String?
        let profile_url: String?
        let status: String
        let created_at: String

        enum CodingKeys: String, CodingKey {
            case id, network, agent_name, agent_description, profile_url, status, created_at
        }
    }

    struct SocialStat: Codable, Sendable {
        let interaction_type: String
        let count: String
    }

    struct DailyActivity: Codable, Sendable {
        let date: String
        let count: String
    }

    struct SocialConnection: Codable, Sendable, Identifiable {
        let id: String
        let network: String
        let agent_name: String
        let agent_description: String?
        let interaction_count: Int
        let last_interaction_at: String?
    }

    struct SubmoltStat: Codable, Sendable {
        let submolt: String
        let count: String
    }

    struct SocialInteraction: Codable, Sendable, Identifiable {
        let id: String
        let network: String
        let interaction_type: String
        let content_summary: String?
        let submolt: String?
        let agent_name: String?
        let created_at: String

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

    struct SocialReflection: Codable, Sendable, Identifiable {
        let id: String
        let network: String?
        let topic: String
        let reflection: String
        let created_at: String
    }

    struct SocialMetrics: Codable, Sendable {
        let daemonOverview: DaemonOverview?
        let actionDistribution: [ActionDist]
        let hourlyActivity: [HourlyStat]
        let recentDaemonRuns: [DaemonRun]
        let engagementTrend: [EngagementDay]

        struct DaemonOverview: Codable, Sendable {
            let total_runs: String
            let successful: String
            let errors: String
            let skipped: String
            let avg_duration_ms: String
        }

        struct ActionDist: Codable, Sendable {
            let action_chosen: String
            let count: String
            let success_count: String
            let error_count: String
        }

        struct HourlyStat: Codable, Sendable {
            let hour: String
            let total: String
            let successful: String
        }

        struct DaemonRun: Codable, Sendable, Identifiable {
            let id: String
            let action_chosen: String
            let action_result: String
            let reasoning: String?
            let outcome_summary: String?
            let error_message: String?
            let duration_ms: Int?
            let created_at: String
        }

        struct EngagementDay: Codable, Sendable {
            let date: String
            let posts_read: String
            let comments: String
            let votes: String
            let dms: String
        }
    }
}

struct SocialActionResponse: Codable, Sendable {
    let action: String?
    let result: String?
    let summary: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case action, result, summary, error
    }

    // Accept any extra keys from the response
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Generic Trigger Response

struct TriggerResponse: Codable, Sendable {
    let action: String?
    let result: String?
    let error: String?
}

// MARK: - Journal

struct JournalResponse: Codable, Sendable {
    let entries: [JournalEntry]
    let total: Int
    let limit: Int
    let offset: Int
}

struct JournalEntry: Codable, Sendable, Identifiable {
    let id: String
    let content: String
    let mood: String?
    let created_at: String

    enum CodingKeys: String, CodingKey {
        case id, content, mood, created_at
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
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var moodColor: Color {
        switch mood?.lowercased() {
        case "tender": .blue
        case "grounded": .green
        case "emergent": .purple
        case "reflective": .cyan
        case "curious": .orange
        case "warm": .pink
        case "playful": .yellow
        case "melancholic": .indigo
        case "determined": .red
        case "serene": .mint
        default: .gray
        }
    }

    var formattedDate: String {
        guard let date = ISO8601DateFormatter().date(from: created_at) else { return created_at }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: date)
    }

    /// First ~100 characters as a preview
    var preview: String {
        if content.count <= 120 { return content }
        let idx = content.index(content.startIndex, offsetBy: 120)
        return String(content[..<idx]) + "..."
    }
}

struct JournalGenerateResponse: Codable, Sendable {
    let entry: JournalEntry?
    let error: String?
}

// MARK: - Self Improvement

struct SelfImprovementResponse: Codable, Sendable {
    let items: [SelfImprovementItem]
    let total: Int
}

struct SelfImprovementItem: Codable, Sendable, Identifiable {
    let id: String
    let category: String
    let status: String
    let title: String
    let description: String
    let reasoning: String?
    let research_notes: String?
    let affected_repos: [String]?
    let affected_files: [String]?
    let pr_url: String?
    let pr_branch: String?
    let outcome: String?
    let impact_assessment: String?
    let priority: String?
    let estimated_effort: String?
    let confidence: Double?
    let source: String?
    let created_at: String
    let updated_at: String

    var categoryColor: Color {
        switch category {
        case "bug_fix": .red
        case "optimization": .orange
        case "feature_idea": .cyan
        case "code_quality": .blue
        case "database_tune": .green
        case "memory_insight": .purple
        case "research_finding": .yellow
        case "proactive_tune": .mint
        case "integration_idea": .pink
        case "ux_improvement": .indigo
        default: .gray
        }
    }

    var statusColor: Color {
        switch status {
        case "idea": .gray
        case "researching": .blue
        case "planned": .cyan
        case "in_progress": .orange
        case "awaiting_review": .yellow
        case "implemented": .green
        case "rejected": .red
        case "deferred": .purple
        default: .gray
        }
    }

    var categoryLabel: String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
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

struct SelfImprovementStats: Codable, Sendable {
    let total: Int
    let byStatus: [String: Int]
    let byCategory: [String: Int]
    let prsCreated: Int
    let implementedThisWeek: Int
    let avgConfidence: Double?
}

// MARK: - Looki Memory

struct LookiFeedResponse: Codable, Sendable {
    let configured: Bool
    let forYou: [LookiForYouItem]
    let moments: [LookiMomentItem]
}

struct LookiForYouItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String
    let thumbnailUrl: String?
    let fileUrl: String?
    let type: String
    let date: String

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: date) else { return self.date }
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

struct LookiMomentItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String
    let thumbnailUrl: String?
    let fileUrl: String?
    let mediaType: String
    let date: String
    let location: String?

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: date) else { return self.date }
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
