import Foundation

/// `POST /api/command/ask` response — the read-only "ask anything" lane of the Command Line.
/// The Nexus backend semantic-searches the unified corpus and ARIA summarizes the result; the
/// model never picks tools, so nothing here can write. `answer` is grounded markdown.
struct CommandAskResponse: Codable, Sendable {
    let answer: String
    let toolCalls: [CommandToolCall]
    let readToolCount: Int
    let steps: Int
    let truncated: Bool
}

/// One read the lane consulted (for a lightweight "consulted: …" receipt under the answer).
struct CommandToolCall: Codable, Sendable, Identifiable {
    let tool: String
    let ok: Bool
    let result: String

    // params is present in the JSON but ignored here (not needed for display).
    enum CodingKeys: String, CodingKey { case tool, ok, result }

    var id: String { tool }
}
