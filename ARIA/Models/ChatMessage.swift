import Foundation
import SwiftData

/// A single message in a conversation, mirroring the server's `messages` table.
@Model
final class ChatMessage {
    @Attribute(.unique) var id: String
    var conversationId: String
    var role: String  // "user" or "assistant"
    var content: String
    var createdAt: Date

    var conversation: Conversation?

    init(id: String, conversationId: String, role: String, content: String, createdAt: Date = .now) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}

/// JSON shape returned by `GET /api/conversations/[id]`.
struct MessageDTO: Codable {
    let id: String
    let conversation_id: String
    let role: String
    let content: String
    let created_at: String

    func toModel() -> ChatMessage {
        ChatMessage(
            id: id,
            conversationId: conversation_id,
            role: role,
            content: content,
            createdAt: DateFormatter.iso8601Full.date(from: created_at) ?? .now
        )
    }
}

struct MessagesResponse: Codable {
    let messages: [MessageDTO]
}
