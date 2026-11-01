import SwiftUI
import AuthenticationServices
import UIKit

/// Manages authentication state using GitHub OAuth via the ARIA backend.
@Observable
@MainActor
final class AuthManager {
    // Hard-coded defaults
    private let defaultServerURL: String = AppConfig.backendBaseURL.absoluteString
    private let useHardCodedToken: Bool = false // Set to true to bypass login entirely
    private let hardCodedToken: String = "" // Put your personal token here if bypassing login
    private let autoStartSSOOnLaunch: Bool = true

    var isAuthenticated: Bool = false
    var serverURL: String = ""
    var isValidating: Bool = false
    var validationError: String?
    var gitHubUsername: String?
    var gitHubAvatarURL: String?

    init() {
        // Always use the default server URL and ensure it's in the shared Keychain
        self.serverURL = defaultServerURL
        KeychainManager.saveServerURL(defaultServerURL)

        // Optionally bypass login entirely with a hard-coded token
        if useHardCodedToken, !hardCodedToken.isEmpty {
            KeychainManager.saveServerURL(defaultServerURL)
            KeychainManager.saveToken(hardCodedToken)
            self.isAuthenticated = true
            self.gitHubUsername = KeychainManager.get(key: "github-username")
            self.gitHubAvatarURL = KeychainManager.get(key: "github-avatar")
            return
        }

        // Check for existing credentials on launch
        if let url = KeychainManager.getServerURL(), let token = KeychainManager.getToken(),
           !url.isEmpty, !token.isEmpty {
            self.serverURL = url
            self.isAuthenticated = true
            self.gitHubUsername = KeychainManager.get(key: "github-username")
            self.gitHubAvatarURL = KeychainManager.get(key: "github-avatar")

            // Validate token in the background and re-authenticate if needed.
            // Only a genuine 401 invalidates the session — a transient failure
            // (offline launch, DNS, 5xx, timeout) must NOT sign the user out,
            // because the sign-out cascade tears down every sync source.
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await APIClient.shared.listConversations()
                } catch APIError.unauthorized {
                    KeychainManager.deleteToken()
                    self.isAuthenticated = false
                    self.startAutoSSOIfNeeded()
                } catch {
                    Logger.shared.logMinimal("auth", "Token validation skipped (transient):", error.localizedDescription)
                }
            }
        } else {
            // Ensure any stale server URL is corrected
            KeychainManager.saveServerURL(defaultServerURL)
            // Automatically start SSO on first launch if enabled
            startAutoSSOIfNeeded()
        }
    }

    private func startAutoSSOIfNeeded() {
        guard autoStartSSOOnLaunch, !useHardCodedToken, !isAuthenticated else { return }
        Task { @MainActor in
            // Small delay to allow the window to be ready for presentation
            try? await Task.sleep(nanoseconds: 300_000_000)
            await loginWithGitHub()
        }
    }

    /// Ensures there is a valid session; if the saved token is invalid or missing, starts SSO.
    /// Transient failures (offline, 5xx) keep the current session — only a real 401 re-logs.
    func ensureAuthenticated() async {
        if isAuthenticated {
            do {
                _ = try await APIClient.shared.listConversations()
                return
            } catch APIError.unauthorized {
                KeychainManager.deleteToken()
                isAuthenticated = false
            } catch {
                return
            }
        }
        await loginWithGitHub()
    }

    /// Start the GitHub OAuth flow using the fixed server's auth endpoint.
    /// The backend handles the OAuth exchange and returns a session token.
    func loginWithGitHub() async {
        // Prevent multiple concurrent SSO sessions
        if isValidating || isAuthenticated {
            return
        }
        isValidating = true
        validationError = nil

        let normalizedURL = defaultServerURL

        // Build the GitHub OAuth URL on the backend
        let callbackScheme = "aria"
        let authURLString = "\(normalizedURL)/auth/github?redirect_uri=\(callbackScheme)://auth/callback"

        guard let authURL = URL(string: authURLString) else {
            validationError = "Invalid server URL"
            isValidating = false
            return
        }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: callbackScheme
                ) { callbackURL, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: AuthError.unknown)
                    }
                }
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = WebAuthPresentationContext.shared
                session.start()
            }

            // Parse the callback URL for the token
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                validationError = "Authentication failed — no token received"
                isValidating = false
                return
            }

            // Extract optional GitHub profile info from callback
            let username = components.queryItems?.first(where: { $0.name == "username" })?.value
            let avatarURL = components.queryItems?.first(where: { $0.name == "avatar_url" })?.value

            // Save credentials
            KeychainManager.saveServerURL(normalizedURL)
            KeychainManager.saveToken(token)
            if let username { KeychainManager.save(key: "github-username", value: username) }
            if let avatarURL { KeychainManager.save(key: "github-avatar", value: avatarURL) }

            // Verify the token works
            _ = try await APIClient.shared.listConversations()

            self.serverURL = normalizedURL
            self.gitHubUsername = username
            self.gitHubAvatarURL = avatarURL
            self.isAuthenticated = true
        } catch is CancellationError {
            validationError = nil // User cancelled
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            validationError = nil // User cancelled
        } catch {
            KeychainManager.deleteToken()
            self.validationError = "Authentication failed: \(error.localizedDescription)"
        }

        isValidating = false
    }

    func logout() {
        KeychainManager.deleteToken()
        KeychainManager.delete(key: "github-username")
        KeychainManager.delete(key: "github-avatar")
        isAuthenticated = false
        serverURL = defaultServerURL
        gitHubUsername = nil
        gitHubAvatarURL = nil

        // Clear the pending sync-staleness nag — a signed-out app must not nag.
        SyncReminderScheduler.shared.cancel()

        // Reset all integration states so they must be reconnected after sign-in
        NotificationCenter.default.post(name: .ariaDidLogout, object: nil)
    }
}

// MARK: - Supporting types

extension Notification.Name {
    static let ariaDidLogout = Notification.Name("ariaDidLogout")
}

enum AuthError: LocalizedError {
    case unknown

    var errorDescription: String? {
        switch self {
        case .unknown: "An unknown authentication error occurred"
        }
    }
}

/// Provides the presentation anchor for ASWebAuthenticationSession.
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
            // UIWindow() is deprecated (iOS 26); bind to the scene.
            return ASPresentationAnchor(windowScene: scene)
        }
        // No window scene: unreachable for an in-app OAuth flow (the app
        // always has a scene while presenting). The bare init is the
        // only way to vend an anchor with no scene to bind, so this one
        // deprecation warning is deliberately retained on a dead path.
        return ASPresentationAnchor()
    }
}
