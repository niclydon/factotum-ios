import Foundation
import LocalAuthentication

/// Manages Face ID / Touch ID app lock.
///
/// The app locks when going to background and requires biometric auth
/// to unlock on return. A grace period prevents re-locking on quick
/// app switches. Background sync services are unaffected.
@Observable
@MainActor
final class BiometricLockService {

    // MARK: - State

    var isLocked = false
    var isAuthenticating = false
    var authError: String?
    private var hasEnteredBackgroundOnce = false

    /// Whether biometric lock is enabled (auto-enabled after first login).
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "biometric_lock_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "biometric_lock_enabled") }
    }

    // MARK: - Private

    private let gracePeriodSeconds: TimeInterval = 5
    private var backgroundedAt: Date?

    // MARK: - Setup

    /// Called once after login. Checks biometric availability on a background thread.
    func enableAfterLogin() {
        if isEnabled {
            // Already enabled from a previous session — don't re-check
            return
        }
        Task.detached {
            let context = LAContext()
            var error: NSError?
            let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            await MainActor.run {
                if available {
                    self.isEnabled = true
                }
            }
        }
    }

    // MARK: - Lock / Unlock

    func appDidEnterBackground() {
        guard isEnabled else { return }
        hasEnteredBackgroundOnce = true
        backgroundedAt = Date()
    }

    func appWillEnterForeground() {
        guard isEnabled, hasEnteredBackgroundOnce else { return }

        if let bg = backgroundedAt {
            let elapsed = Date().timeIntervalSince(bg)
            if elapsed > gracePeriodSeconds {
                isLocked = true
            }
        }
        backgroundedAt = nil
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    func unlock() {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil

        Task.detached {
            let context = LAContext()
            context.localizedFallbackTitle = "Use Passcode"

            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock ARIA"
                )
                await MainActor.run {
                    self.isAuthenticating = false
                    if success {
                        self.isLocked = false
                    } else {
                        self.authError = "Authentication failed"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authError = error.localizedDescription
                }
            }
        }
    }

    func disable() {
        isEnabled = false
        isLocked = false
        backgroundedAt = nil
    }
}
