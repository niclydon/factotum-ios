import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ARIATheme.background.ignoresSafeArea()

                // Subtle background glow — scales with screen
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ARIATheme.accent.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: min(geo.size.width, geo.size.height) * 0.5
                        )
                    )
                    .frame(width: geo.size.width, height: geo.size.width)
                    .offset(y: -80)

                VStack(spacing: layout.sized(phone: 32, pad: 40)) {
                    Spacer()

                    Image("ARIAProfile")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: layout.profileImageLarge, height: layout.profileImageLarge)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(ARIATheme.accentCyan.opacity(0.3), lineWidth: 1.5)
                        )

                    VStack(spacing: 6) {
                        Text("Factotum")
                            .font(.system(size: layout.titleSize, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [ARIATheme.accent, ARIATheme.accentCyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("Personal AI Assistant")
                            .font(.system(size: layout.subtitleSize))
                            .foregroundStyle(ARIATheme.textSecondary)
                    }

                    if let error = auth.validationError {
                        Text(error)
                            .font(layout.adaptiveCaptionFont)
                            .foregroundStyle(ARIATheme.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button {
                        Task { await auth.loginWithGitHub() }
                    } label: {
                        Group {
                            if auth.isValidating {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: layout.sized(phone: 16, pad: 18)))
                                    Text("Sign in with GitHub")
                                        .font(.system(size: layout.fontBody, weight: .semibold))
                                }
                            }
                        }
                        .frame(width: layout.buttonWidth, height: layout.buttonHeight)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(auth.isValidating)

                    Spacer()
                    Spacer()

                    Text(AppConfig.backendBaseURL.host ?? "api.example.com")
                        .font(.system(size: layout.sized(phone: 11, pad: 13)))
                        .foregroundStyle(ARIATheme.textMuted)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: layout.maxContentWidth)
            }
        }
        .task {
            await auth.ensureAuthenticated()
        }
    }
}
