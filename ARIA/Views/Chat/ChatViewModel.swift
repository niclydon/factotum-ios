import SwiftUI
import SwiftData

/// View model for the main chat interface. Handles conversation state,
/// message sending, and SSE stream consumption.
@Observable
@MainActor
final class ChatViewModel {
    // MARK: - Internal block stripping

    /// Strips <journal_note> and <memory_update> XML blocks from streamed text.
    private static func stripInternalBlocks(_ text: String) -> String {
        var result = text
        // Strip complete blocks
        let patterns = [
            #"<journal_note>[\s\S]*?</journal_note>"#,
            #"<memory_update>[\s\S]*?</memory_update>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        // Strip partial opening tags at the end (still streaming)
        let partials = [
            #"<journal_note>[\s\S]*$"#,
            #"<memory_update>[\s\S]*$"#,
        ]
        for pattern in partials {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Published state

    var conversations: [Conversation] = []
    var currentConversation: Conversation?
    var messages: [ChatMessage] = []
    var streamingText: String = ""
    private var rawAccumulator: String = ""
    var statusText: String = ""
    var isStreaming: Bool = false
    var inputText: String = ""
    var error: String?
    var isLoadingConversations: Bool = false
    var showSidebar: Bool = false
    /// Photo thumbnails from photo_search results, keyed by message ID
    var messagePhotos: [String: [ChatPhotoResult]] = [:]
    private var pendingPhotos: [ChatPhotoResult] = []
    /// The model that generated each assistant message, keyed by message ID.
    /// Captured from the `done` SSE event's `model` field. Rendered as a small
    /// grey footer below each assistant bubble (matches Desk's UX). Stored
    /// off-message to avoid a SwiftData @Model schema migration.
    var messageModels: [String: String] = [:]
    /// Currently-selected model for outbound chat. nil = let server pick its
    /// default. Set by ModelPickerView in the sidebar.
    var selectedModel: String?
    /// Catalog of models Forge exposes. Loaded lazily on sidebar open via
    /// loadAvailableModels(). Empty until then.
    var availableModels: [APIClient.ForgeModel] = []

    // MARK: - Dependencies

    private let api = APIClient.shared

    // MARK: - Conversations
    //
    // Post-Phase-5, ARIA is a single thread on channel='aria-direct' shared
    // by Desk, the iMessage relay, and (now) iOS. The legacy multi-conversation
    // model (per-conversation IDs in the `conversations` table) is retired.
    // We keep the per-conversation API surface for view compatibility but
    // back it with a single virtual entry pointing at the aria-direct channel.

    /// The channel id Nexus uses for the canonical ARIA chat thread.
    /// Same id Desk's /aria thread reads/writes and the chat endpoint persists into.
    private static let ariaChannelId = "aria-direct"

    func loadConversations() async {
        // No legacy list to load anymore — fabricate a single virtual
        // conversation entry pointing at aria-direct so views that iterate
        // over `conversations` still have something to render. Title is
        // populated lazily once we have the latest message.
        isLoadingConversations = true
        let single = Conversation(
            id: Self.ariaChannelId,
            title: "ARIA",
            createdAt: .now,
            updatedAt: .now,
        )
        conversations = [single]
        if currentConversation == nil {
            currentConversation = single
            await loadMessages(for: Self.ariaChannelId)
        }
        SpotlightIndexer.indexConversations(conversations)
        isLoadingConversations = false
    }

    func selectConversation(_ conversation: Conversation) async {
        currentConversation = conversation
        showSidebar = false
        await loadMessages(for: conversation.id)
    }

    func newConversation() {
        // "New conversation" used to wipe state to start a fresh thread.
        // The aria-direct model is one continuous thread, but we still let
        // the user clear the local view if they want a clean visual reset
        // — server history is unaffected.
        messages = []
        streamingText = ""
        statusText = ""
        inputText = ""
        error = nil
        showSidebar = false
        // Keep currentConversation pointed at aria-direct.
    }

    func deleteConversation(_ conversation: Conversation) async {
        // No-op against the single virtual conversation. Real history
        // deletion would have to happen against channel_messages on the
        // server, which we don't expose to the iOS app.
        newConversation()
    }

    // MARK: - Messages

    func loadMessages(for conversationId: String) async {
        // Always load from the aria-direct channel — conversationId is
        // ignored since there's only one thread now.
        do {
            let dtos = try await api.loadAriaHistory(limit: 50)
            messages = dtos.map { $0.toModel() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Voice Mode

    /// Send a message in voice mode. Doesn't use inputText — takes content directly.
    /// Waits for the full response before returning (so VoiceSessionView can speak it).
    func sendVoiceMessage(_ content: String) async {
        guard !content.isEmpty, !isStreaming else { return }

        isStreaming = true
        streamingText = ""
        rawAccumulator = ""
        statusText = ""
        error = nil

        pendingPhotos = []
        let turns = Self.buildChatTurns(messages: messages)
        let stream = await api.sendMessage(messages: turns, model: selectedModel, voiceMode: true)
        await consumeChatStream(stream)
    }

    // MARK: - Send & Stream

    func send() async {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isStreaming else { return }

        // Add user message optimistically (server will also persist it via
        // /v1/chat/aria → channel_messages, but the UI shouldn't wait).
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            conversationId: Self.ariaChannelId,
            role: "user",
            content: content,
        )
        messages.append(userMessage)
        inputText = ""
        isStreaming = true
        streamingText = ""
        rawAccumulator = ""
        statusText = ""
        error = nil

        pendingPhotos = []
        let turns = Self.buildChatTurns(messages: messages)
        let stream = await api.sendMessage(messages: turns, model: selectedModel)
        await consumeChatStream(stream)
    }

    /// Fetch the picker's model catalog from Forge (via Nexus passthrough).
    /// Called by the sidebar on open. Idempotent / safe to call repeatedly —
    /// just refreshes the list. Errors are non-fatal — picker shows nothing
    /// if Forge is unreachable; the chat path still works via the server's
    /// default model.
    func loadAvailableModels() async {
        do {
            availableModels = try await api.listForgeModels()
        } catch {
            // Intentionally swallowed.
        }
    }

    // MARK: - Stream consumer
    //
    // Shared by send() and sendVoiceMessage() — both build a turns array
    // from the current messages state and consume the named-event SSE the
    // same way. The body used to be inlined twice; pulling it out keeps the
    // mapping from ChatEvent → view state in one place.
    private func consumeChatStream(_ stream: AsyncStream<ChatEvent>) async {
        for await event in stream {
            switch event {
            case .start:
                // /v1/chat/aria doesn't emit start. Legacy event from the
                // old /api/chat path — kept for safety in case anything
                // still hits that endpoint.
                break

            case .status(let text):
                statusText = text

            case .chunk(let text):
                statusText = ""
                rawAccumulator += text
                streamingText = Self.stripInternalBlocks(rawAccumulator)

            case .photos(let photos):
                pendingPhotos = photos

            case .done(let messageId, let model):
                let cleanContent = Self.stripInternalBlocks(rawAccumulator)
                let resolvedId = messageId.isEmpty ? UUID().uuidString : messageId
                let assistantMessage = ChatMessage(
                    id: resolvedId,
                    conversationId: Self.ariaChannelId,
                    role: "assistant",
                    content: cleanContent,
                )
                messages.append(assistantMessage)
                if !pendingPhotos.isEmpty {
                    messagePhotos[resolvedId] = pendingPhotos
                    pendingPhotos = []
                }
                if let model {
                    messageModels[resolvedId] = model
                }
                streamingText = ""
                rawAccumulator = ""
                statusText = ""
                isStreaming = false

            case .error(let message):
                self.error = message
                streamingText = ""
                rawAccumulator = ""
                statusText = ""
                isStreaming = false
            }
        }

        // If the stream ended without a `done` event (e.g. server closed
        // the connection mid-flight), still capture whatever was streamed
        // as a finalised message so the UI doesn't lose the partial reply.
        if isStreaming {
            if !rawAccumulator.isEmpty {
                let cleanContent = Self.stripInternalBlocks(rawAccumulator)
                let msg = ChatMessage(
                    id: UUID().uuidString,
                    conversationId: Self.ariaChannelId,
                    role: "assistant",
                    content: cleanContent,
                )
                messages.append(msg)
                streamingText = ""
                rawAccumulator = ""
            }
            isStreaming = false
        }
    }

    /// Build the messages array Nexus's /v1/chat/aria expects: full chat
    /// history as [{role, content}]. The server uses this for context;
    /// it persists only the latest user turn into channel_messages itself
    /// (history is reconstructed server-side from the same channel — but
    /// during the streaming request we still need to send it because the
    /// agent prompt builder uses what's in the request body).
    private static func buildChatTurns(messages: [ChatMessage]) -> [APIClient.ChatTurn] {
        messages.map { APIClient.ChatTurn(role: $0.role, content: $0.content) }
    }
}
