import Foundation
import SwiftUI

struct InboxItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let category: String
    let urgency: String
    let source: String
    let sourceId: String?
    let insightId: String?
    let conversationId: String?
    var isRead: Bool
    var readAt: String?
    var feedbackRating: Int?
    var feedbackComment: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body, category, urgency, source
        case sourceId = "source_id"
        case insightId = "insight_id"
        case conversationId = "conversation_id"
        case isRead = "is_read"
        case readAt = "read_at"
        case feedbackRating = "feedback_rating"
        case feedbackComment = "feedback_comment"
        case createdAt = "created_at"
    }

    var isInsight: Bool { insightId != nil }
    var isUrgent: Bool { urgency == "urgent" }
    var needsFeedback: Bool { isInsight && feedbackRating == nil }

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: createdAt) else { return createdAt }
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
        case "proactive_insight": .purple
        case "self_improvement": .cyan
        case "sensor_hygiene": .green
        case "diagnostic": .orange
        case "daily_briefing": .blue
        case "digest": .indigo
        default: .gray
        }
    }

    var categoryLabel: String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct InboxListResponse: Codable, Sendable {
    let items: [InboxItem]
    let total: Int
    let unreadCount: Int
}

struct UnreadCountResponse: Codable, Sendable {
    let unreadCount: Int
}
