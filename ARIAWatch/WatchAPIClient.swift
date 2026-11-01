import Foundation
import Security

/// Lightweight HTTP client for the Apple Watch.
/// Communicates directly with the ARIA server over HTTP (watchOS 10+).
/// Reads the auth token from the shared Keychain (same team signing + app group).
actor WatchAPIClient {
    static let shared = WatchAPIClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Keychain (matches KeychainManager on iOS)

    private static let keychainService = "com.example.factotum"
    private static let tokenKey = "api-token"
    private static let serverURLKey = "server-url"

    private var authToken: String? {
        Self.keychainGet(key: Self.tokenKey)
    }

    private var baseURL: String {
        Self.keychainGet(key: Self.serverURLKey) ?? "https://api.example.com"
    }

    private static func keychainGet(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: "group.com.example.factotum",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - API

    /// Send a quick question to ARIA and get a text response.
    /// Consumes the SSE stream and concatenates all chunk text.
    func askQuestion(_ question: String) async throws -> String {
        guard let token = authToken else {
            throw WatchAPIError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = ["content": question]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw WatchAPIError.serverError
        }

        // Parse SSE response -- collect text from "chunk" events
        let text = String(data: data, encoding: .utf8) ?? ""
        var result = ""
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let jsonData = jsonStr.data(using: .utf8),
                  let event = try? JSONDecoder().decode(SSEEvent.self, from: jsonData),
                  event.type == "chunk"
            else { continue }
            result += event.text ?? ""
        }

        return TextSanitizer.sanitize(result.isEmpty ? text : result)
    }

    // MARK: - Errors

    enum WatchAPIError: LocalizedError {
        case notAuthenticated
        case serverError

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: "Not signed in. Open ARIA on your iPhone first."
            case .serverError: "Could not reach ARIA."
            }
        }
    }
}

// MARK: - DTOs

struct SSEEvent: Codable, Sendable {
    let type: String?
    let text: String?
}
