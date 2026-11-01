import SwiftUI

/// Branded splash screen shown during app launch.
struct SplashView: View {
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        ZStack {
            ARIATheme.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layout.profileImageLarge, height: layout.profileImageLarge)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(ARIATheme.accentCyan.opacity(0.3), lineWidth: 1.5)
                    )

                Text("Factotum")
                    .font(.system(size: layout.titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ARIATheme.accent, ARIATheme.accentCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .frame(maxWidth: layout.maxContentWidth)
        }
    }
}
