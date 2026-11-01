import Foundation
import SwiftData

/// A chat conversation, mirroring the server's `conversations` table.
@Model
final class Conversation {
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastMessage: String?
    var personaId: String?
    var personaSlug: String?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(id: String, title: String, createdAt: Date = .now, updatedAt: Date = .now, lastMessage: String? = nil, personaId: String? = nil, personaSlug: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessage = lastMessage
        self.personaId = personaId
        self.personaSlug = personaSlug
    }
}

/// JSON shape returned by `GET /api/conversations`.
struct ConversationDTO: Codable {
    let id: String
    let title: String
    let created_at: String
    let updated_at: String
    let last_message: String?
    let persona_id: String?
    let persona_slug: String?

    func toModel() -> Conversation {
        Conversation(
            id: id,
            title: title,
            createdAt: DateFormatter.iso8601Full.date(from: created_at) ?? .now,
            updatedAt: DateFormatter.iso8601Full.date(from: updated_at) ?? .now,
            lastMessage: last_message,
            personaId: persona_id,
            personaSlug: persona_slug
        )
    }
}

struct ConversationsResponse: Codable {
    let conversations: [ConversationDTO]
}

struct ConversationCreateResponse: Codable {
    let conversation: ConversationDTO
}

/// A message row returned by Nexus's /v1/channels/:id/history. Matches the
/// channel_messages table that Desk and the iMessage relay also read from.
/// We use this to hydrate the iOS chat thread on open from the same source
/// of truth Desk uses, rather than the legacy iOS-only conversations table.
struct ChannelMessageDTO: Codable {
    let id: Int
    let channel_id: String
    let sender_id: String
    let message_type: String?
    let content: String
    let created_at: String

    /// Map sender_id ('user' / 'assistant') to ChatMessage's role.
    /// Anything else gets "assistant" as a safe default — most
    /// non-user senders are agent-side (assistant, system, tool relays).
    var role: String {
        sender_id == "user" ? "user" : "assistant"
    }

    func toModel() -> ChatMessage {
        ChatMessage(
            id: String(id),
            conversationId: channel_id,
            role: role,
            content: content,
            createdAt: DateFormatter.iso8601Full.date(from: created_at) ?? .now,
        )
    }
}

struct ChannelHistoryResponse: Codable {
    let messages: [ChannelMessageDTO]
    let has_more: Bool?
}
