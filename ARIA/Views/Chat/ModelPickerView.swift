import SwiftUI

/// Sidebar replacement for ConversationListView. The Phase-5 chat model
/// collapses to a single thread (channel='aria-direct'), so per-conversation
/// switching is gone — the sidebar's job becomes model selection plus the
/// inbox link. Mirrors Desk's ModelPicker shape: two sections (forge local +
/// cloud passthrough) with the active selection highlighted.
struct ModelPickerView: View {
    let models: [APIClient.ForgeModel]
    let selectedModel: String?
    let isLoading: Bool
    let onSelectModel: (String?) -> Void
    let onClearChat: () -> Void

    @Environment(\.adaptiveLayout) private var layout

    private var localModels: [APIClient.ForgeModel] {
        models.filter { $0.isLocal }.sorted { $0.id < $1.id }
    }

    private var cloudModels: [APIClient.ForgeModel] {
        models.filter { !$0.isLocal }.sorted { $0.id < $1.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Model")
                    .font(layout.adaptiveTitleFont)
                    .foregroundStyle(ARIATheme.textPrimary)
                Spacer()
                Button(action: onClearChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                        .foregroundStyle(ARIATheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().overlay(ARIATheme.border)


            Divider().overlay(ARIATheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading && models.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading models...")
                                .font(layout.adaptiveCaptionFont)
                                .foregroundStyle(ARIATheme.textMuted)
                        }
                        .padding(16)
                    }

                    // "Default" row at the top — picks nil so the server's
                    // own default applies. Matches Desk's "default" pseudo-row.
                    sectionHeader("Default")
                    pickerRow(
                        id: nil,
                        label: "Server default",
                        hint: "ARIA picks the right model for this turn",
                    )

                    if !localModels.isEmpty {
                        sectionHeader("Forge (local)")
                        ForEach(localModels) { m in
                            pickerRow(id: m.id, label: m.id, hint: nil)
                        }
                    }

                    if !cloudModels.isEmpty {
                        sectionHeader("Cloud (Forge passthrough)")
                        ForEach(cloudModels) { m in
                            pickerRow(id: m.id, label: m.id, hint: m.provider)
                        }
                    }
                }
            }
        }
        .background(ARIATheme.surface)
        // Inbox unread count is not surfaced here yet — would need a Nexus
        // /v1/aria-inbox/unread-count or similar. Left as a future polish;
        // the badge stays hidden when count==0 so the row reads cleanly.
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(ARIATheme.textMuted)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func pickerRow(id: String?, label: String, hint: String?) -> some View {
        let isActive = id == selectedModel
        return Button {
            onSelectModel(id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "circle.inset.filled" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? ARIATheme.accent : ARIATheme.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: layout.sized(phone: 13, pad: 14), design: .monospaced))
                        .foregroundStyle(isActive ? ARIATheme.textPrimary : ARIATheme.textSecondary)
                    if let hint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 10))
                            .foregroundStyle(ARIATheme.textMuted)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
