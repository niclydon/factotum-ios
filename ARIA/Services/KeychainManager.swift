import Foundation
import Security

/// Minimal Keychain wrapper for storing ARIA credentials.
/// Credentials are accessible to the main app, Share Extension, and Watch app
/// via the shared Keychain access group.
enum KeychainManager {
    private static let service = "com.example.factotum"
    private static let accessGroup = "group.com.example.factotum"
    private static let tokenKey = "api-token"
    private static let serverURLKey = "server-url"

    // MARK: - API Token

    static func saveToken(_ token: String) {
        save(key: tokenKey, value: token)
    }

    static func getToken() -> String? {
        get(key: tokenKey)
    }

    static func deleteToken() {
        delete(key: tokenKey)
    }

    // MARK: - Server URL

    static func saveServerURL(_ url: String) {
        save(key: serverURLKey, value: url)
    }

    static func getServerURL() -> String? {
        get(key: serverURLKey)
    }

    // MARK: - Migration

    /// Migrate keychain items saved without access group to the shared group.
    /// Called once on app launch so existing users don't lose auth.
    static func migrateToSharedGroup() {
        for key in [tokenKey, serverURLKey] {
            // Try reading WITHOUT access group (old format)
            let oldQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(oldQuery as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else { continue }

            // Check if it already exists in the shared group
            if get(key: key) != nil { continue }

            // Save to shared group
            save(key: key, value: value)

            // Delete the old item (without access group)
            SecItemDelete(oldQuery as CFDictionary)
        }
    }

    // MARK: - Generic helpers

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
