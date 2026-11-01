import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var photos: [ChatPhotoResult] = []
    var personaSlug: String? = nil
    /// Model name reported by the server's `done` event (e.g. "example-chat-model").
    /// Rendered as a small grey footer below the bubble for assistant messages.
    var model: String? = nil
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: layout.messageMinSpacing)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Role label with ARIA profile picture
                if message.isAssistant {
                    HStack(spacing: 6) {
                        Image(personaAvatarName(for: personaSlug))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: layout.profileImageChat, height: layout.profileImageChat)
                            .clipShape(Circle())
                        Text("ARIA")
                            .font(.system(size: layout.isRegular ? 13 : 11, weight: .semibold))
                            .foregroundStyle(ARIATheme.accentCyan)
                    }
                }

                // Content
                Text(attributedContent)
                    .font(layout.adaptiveBodyFont)
                    .foregroundStyle(ARIATheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, layout.messageBubblePadding)
                    .padding(.vertical, 10)
                    .background(message.isUser ? ARIATheme.userBubble : ARIATheme.assistantBubble)
                    .clipShape(RoundedRectangle(cornerRadius: ARIATheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: ARIATheme.cornerRadius)
                            .stroke(
                                message.isUser ? ARIATheme.accent.opacity(0.3) : ARIATheme.border,
                                lineWidth: 0.5
                            )
                    )

                // Inline photo thumbnails from photo_search
                if !photos.isEmpty {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(photos) { photo in
                            if let url = photo.thumbnailURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 80)
                                            .clipped()
                                    case .failure:
                                        photoPlaceholder
                                    default:
                                        ProgressView()
                                            .tint(ARIATheme.textMuted)
                                            .frame(height: 80)
                                            .frame(maxWidth: .infinity)
                                            .background(ARIATheme.surface)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }

                // Timestamp. (The thumbs up/down feedback buttons were removed
                // 2026-09-25: /api/messages/:id/feedback has no Nexus handler, so
                // every tap 404'd and the selection silently reverted.)
                if !isStreaming {
                    HStack(spacing: 8) {
                        Text(message.createdAt, style: .time)
                            .font(.system(size: layout.sized(phone: 10, pad: 12)))
                            .foregroundStyle(ARIATheme.textMuted)
                    }
                }

                // Model label — small grey monospace text identifying which
                // model generated this assistant response. Only shows for
                // assistant messages where the server reported a model in
                // its `done` event payload (older messages may not have
                // one if the agent task ran before model reporting landed).
                if !isStreaming, message.isAssistant, let modelName = model, !modelName.isEmpty {
                    Text(modelName)
                        .font(.system(size: layout.sized(phone: 9, pad: 11), design: .monospaced))
                        .foregroundStyle(ARIATheme.textMuted)
                }
            }
            .frame(maxWidth: layout.isRegular ? 500 : .infinity, alignment: message.isUser ? .trailing : .leading)

            if message.isAssistant {
                Spacer(minLength: layout.messageMinSpacing)
            }
        }
    }

    /// Maps a persona slug (e.g. "warm-companion") to an asset catalog image name
    /// (e.g. "PersonaAvatarWarmCompanion"). Falls back to "ARIAProfile" when nil.
    private func personaAvatarName(for slug: String?) -> String {
        guard let slug = slug else { return "ARIAProfile" }
        let parts = slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return "PersonaAvatar" + parts.joined()
    }

    private var photoPlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 16))
            .foregroundStyle(ARIATheme.textMuted.opacity(0.4))
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(ARIATheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Basic markdown-like rendering: **bold** and `code`.
    private var attributedContent: AttributedString {
        var result = AttributedString(TextSanitizer.sanitize(message.content))

        // Bold: **text**
        while let boldStart = result.range(of: "**") {
            let afterStart = boldStart.upperBound
            guard let boldEnd = result[afterStart...].range(of: "**") else { break }
            let boldRange = afterStart..<boldEnd.lowerBound

            result[boldRange].font = .system(size: layout.fontBody, weight: .bold)
            result.removeSubrange(boldEnd)
            result.removeSubrange(boldStart)
        }

        // Inline code: `text`
        while let codeStart = result.range(of: "`") {
            let afterStart = codeStart.upperBound
            guard let codeEnd = result[afterStart...].range(of: "`") else { break }
            let codeRange = afterStart..<codeEnd.lowerBound

            result[codeRange].font = .system(size: layout.fontSubheadline, design: .monospaced)
            result[codeRange].backgroundColor = ARIATheme.surface
            result.removeSubrange(codeEnd)
            result.removeSubrange(codeStart)
        }

        return result
    }
}
