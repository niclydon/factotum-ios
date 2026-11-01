import SwiftUI

struct ReviewActionButtons: View {
    let actions: [ReviewAction]
    let disabled: Bool
    let onTap: (ReviewAction) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(actions, id: \.decision) { action in
                Button { onTap(action) } label: {
                    Text(action.label).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.color(for: action.style))
                .disabled(disabled)
            }
        }
    }

    static func color(for style: ReviewAction.Style) -> Color {
        switch style {
        case .success: ARIATheme.success
        case .danger: ARIATheme.error
        case .primary: ARIATheme.accent
        case .secondary: ARIATheme.textSecondary
        }
    }
}
