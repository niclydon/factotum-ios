import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onVoiceTap: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message ARIA...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(layout.adaptiveBodyFont)
                .foregroundStyle(ARIATheme.textPrimary)
                .lineLimit(1...(layout.isRegular ? 10 : 6))
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(ARIATheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(isFocused ? ARIATheme.accent.opacity(0.5) : ARIATheme.border, lineWidth: 1)
                )
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            if canSend || isStreaming {
                Button {
                    onSend()
                } label: {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: layout.sized(phone: 32, pad: 36)))
                        .foregroundStyle(ARIATheme.accent)
                }
                .disabled(!canSend && !isStreaming)
            } else {
                Button {
                    onVoiceTap()
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: layout.sized(phone: 32, pad: 36)))
                        .foregroundStyle(ARIATheme.accentCyan)
                }
            }
        }
        .padding(.horizontal, layout.screenPadding)
        .padding(.vertical, 10)
        .background(ARIATheme.background)
        // Drag & drop text/URLs into chat (iPad)
        .dropDestination(for: String.self) { items, _ in
            if let dropped = items.first {
                text += (text.isEmpty ? "" : "\n") + dropped
                return true
            }
            return false
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }
}
