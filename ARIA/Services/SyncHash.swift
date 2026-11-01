import Foundation
import CryptoKit

/// Utility for detecting whether synced data has changed since the last push.
///
/// Encodes a Codable payload to JSON, hashes it with SHA256, and compares
/// against the stored hash in UserDefaults. If unchanged, the sync can be skipped.
enum SyncHash {

    /// Returns `true` if the data has changed since the last sync (or if no prior hash exists).
    static func hasChanged<T: Encodable>(_ data: T, key: String) -> Bool {
        guard let jsonData = try? JSONEncoder().encode(data) else { return true }
        let hash = SHA256.hash(data: jsonData)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()

        let storedHash = UserDefaults.standard.string(forKey: "sync_hash_\(key)")
        return hashString != storedHash
    }

    /// Store the hash of the data after a successful sync.
    static func save<T: Encodable>(_ data: T, key: String) {
        guard let jsonData = try? JSONEncoder().encode(data) else { return }
        let hash = SHA256.hash(data: jsonData)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hashString, forKey: "sync_hash_\(key)")
    }
}
