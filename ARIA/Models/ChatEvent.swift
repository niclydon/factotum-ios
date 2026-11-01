import Foundation

/// Events surfaced to ChatViewModel from the SSE chat stream.
///
/// Source protocol is Nexus's named-event SSE on /v1/chat/aria (same protocol
/// Desk consumes). The named events on the wire are:
///   event: text.delta        data: {delta:"..."}
///   event: reasoning.delta   data: {delta:"..."}
///   event: tool-call.start   data: {id, name, args}
///   event: tool-call.result  data: {id, output}
///   event: done              data: {message_id?, usage?, model?}
///   event: error             data: {message}
///
/// We map these into a smaller iOS-facing enum that the UI already understands,
/// flattening tool-call events into status text for now (see comments below).
/// Reasoning deltas are dropped — could surface them as a separate "thinking"
/// block in a future pass; not load-bearing for the minimum-viable port.
enum ChatEvent {
    case start(conversationId: String)
    case status(text: String)
    case chunk(text: String)
    case photos(photos: [ChatPhotoResult])
    case done(messageId: String, model: String?)
    case error(message: String)

    /// Parse one SSE block (event-name + joined data string) into a ChatEvent.
    /// Returns nil if the block isn't a recognised event type — caller logs
    /// unknowns at debug level and ignores them.
    static func fromSSEBlock(eventName: String?, data: String) -> ChatEvent? {
        let parsed: [String: Any] = {
            guard let raw = data.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                return [:]
            }
            return obj
        }()

        // Nexus's primary path is `event: <name>` framing, but the AI SDK
        // adapter also fires plain `data: {type:...}` payloads in some flows.
        // Accept either shape for the event name (matches how Desk's parser
        // works — see desk/src/lib/chat/nexus-transport.ts).
        let name = eventName?.isEmpty == false ? eventName! : (parsed["type"] as? String ?? "")

        switch name {
        case "text.delta", "text-delta", "chunk":
            // Old protocol used "text"; new protocol uses "delta".
            let delta = (parsed["delta"] as? String) ?? (parsed["text"] as? String) ?? ""
            guard !delta.isEmpty else { return nil }
            return .chunk(text: delta)

        case "reasoning.delta", "reasoning-delta":
            // Skip for now — could become a separate ChatEvent.reasoning case
            // and a collapsible "thinking" disclosure in the bubble view.
            return nil

        case "tool-call.start", "tool-call-start", "tool.call.start":
            // Surface tool calls as status text so the user sees something
            // happening ("Using gmail__search_emails…"). Phase 2 could render
            // these as proper collapsible cards with args + result.
            let toolName = (parsed["name"] as? String) ?? "tool"
            return .status(text: "Using \(toolName)…")

        case "tool-call.result", "tool-call-result", "tool.call.result":
            // The agent typically follows a tool result with text.delta
            // events that explain the result. Clearing status here keeps
            // the UI from getting stuck on "Using …" after the call returns.
            return .status(text: "")

        case "done", "finish":
            let messageId = (parsed["message_id"] as? String) ?? (parsed["messageId"] as? String) ?? ""
            // Forge reports the actual model used in the done event payload.
            // We surface this in the iOS chat UI as a small grey footer
            // below each assistant bubble so the user sees which model
            // generated the response (matches Desk's UX). May be nil when
            // the agent task ran before model detection landed in
            // packages/worker/src/agent-task-runner.ts (no harm, footer
            // just renders nothing).
            let model = parsed["model"] as? String
            return .done(messageId: messageId, model: model)

        case "error":
            let message = (parsed["message"] as? String) ?? (parsed["error"] as? String) ?? "Unknown error"
            return .error(message: message)

        case "start":
            // Legacy event from /api/chat — kept for backward compat with the
            // old endpoint in case anything still hits it. /v1/chat/aria
            // doesn't emit this.
            let conversationId = (parsed["conversationId"] as? String) ?? ""
            return .start(conversationId: conversationId)

        case "status":
            // Same — legacy.
            let text = (parsed["text"] as? String) ?? ""
            return .status(text: text)

        case "photos":
            // Same — legacy.
            guard let photosArray = parsed["photos"] as? [[String: Any]] else { return nil }
            let photos = photosArray.compactMap { ChatPhotoResult(from: $0) }
            return .photos(photos: photos)

        default:
            return nil
        }
    }
}

/// A photo result included in the SSE stream from photo_search tool calls.
struct ChatPhotoResult: Identifiable, Sendable {
    let id: String
    let description: String?
    let thumbnailUrl: String?
    let takenAt: String?

    var thumbnailURL: URL? {
        guard let thumbnailUrl,
              let baseURL = KeychainManager.getServerURL() else { return nil }
        return URL(string: "\(baseURL)\(thumbnailUrl)")
    }

    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        self.description = dict["description"] as? String
        self.thumbnailUrl = dict["thumbnail_url"] as? String
        self.takenAt = dict["taken_at"] as? String
    }
}
