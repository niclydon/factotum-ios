import SwiftUI

/// Full-screen overlay shown when the app is locked.
struct LockScreenView: View {
    @Environment(BiometricLockService.self) private var lockService
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        ZStack {
            ARIATheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layout.profileImageMedium, height: layout.profileImageMedium)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(ARIATheme.accentCyan.opacity(0.3), lineWidth: 1.5)
                    )

                Text("Factotum is Locked")
                    .font(.system(size: layout.sized(phone: 22, pad: 28), weight: .bold, design: .rounded))
                    .foregroundStyle(ARIATheme.textPrimary)

                Text("Authenticate to continue")
                    .font(layout.adaptiveCaptionFont)
                    .foregroundStyle(ARIATheme.textSecondary)

                Button {
                    lockService.unlock()
                } label: {
                    HStack(spacing: 8) {
                        if lockService.isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                                .font(.system(size: layout.sized(phone: 18, pad: 22)))
                            Text("Unlock with Face ID")
                                .font(.system(size: layout.fontBody, weight: .semibold))
                        }
                    }
                    .frame(width: layout.buttonWidth, height: layout.buttonHeight)
                    .background(ARIATheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(lockService.isAuthenticating)

                if let error = lockService.authError {
                    Text(error)
                        .font(layout.adaptiveCaptionFont)
                        .foregroundStyle(ARIATheme.error)
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .task {
            // Wait for view to fully render before triggering Face ID
            try? await Task.sleep(nanoseconds: 800_000_000)
            if lockService.isLocked {
                lockService.unlock()
            }
        }
    }
}
