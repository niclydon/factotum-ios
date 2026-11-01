import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(DeepLinkManager.self) private var deepLink
    @Environment(BiometricLockService.self) private var lockService
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                Group {
                    if auth.isAuthenticated {
                        RootTabView()
                    } else {
                        LoginView()
                    }
                }
                .transition(.opacity)

                if lockService.isLocked {
                    LockScreenView()
                }
            }
        }
        .onOpenURL { url in deepLink.handle(url: url) }
        .adaptiveLayout()
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSplash = false
        }
    }
}
