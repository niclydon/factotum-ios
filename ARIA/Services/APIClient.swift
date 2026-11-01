import Foundation

/// HTTP client for the ARIA API. Attaches bearer token auth to all requests.
actor APIClient {
    static let shared = APIClient()

    let session: URLSession
    let decoder: JSONDecoder
    private let logger = Logger.shared

    private init() {
        let config = URLSessionConfiguration.default
        // timeoutIntervalForRequest is the *inter-data* timeout, not the
        // time-to-first-byte. For chat SSE this matters: llama-swap may
        // take 10-30s to load a freshly-picked model before any tokens
        // stream, and during that window URLSession sees zero bytes and
        // bails at the 30s default. Bumped to 180s — covers cold-start
        // model swaps comfortably while still catching genuinely-stalled
        // connections. timeoutIntervalForResource caps the total stream
        // duration at 300s (the agent task itself logs 58s on permissive
        // generation, well under that). See nexus log on 2026-04-27 for
        // the incident this guards against.
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    /// The base URL for the backend API (e.g. "https://api.example.com").
    var baseURL: String {
        KeychainManager.getServerURL() ?? ""
    }

    private var token: String? {
        KeychainManager.getToken()
    }

    // MARK: - Chat (SSE streaming)

    /// A user/assistant message turn as expected by Nexus's /v1/chat/aria.
    /// Same shape Desk's NexusChatTransport posts (messages array of role+content).
    struct ChatTurn: Codable, Sendable {
        let role: String
        let content: String
    }

    /// One entry from Forge's /v1/models — surfaced via Nexus's /v1/forge/models
    /// passthrough. Same shape Desk's ModelPicker consumes. We only decode the
    /// fields we actually use; Forge emits more (memory_gb, compute,
    /// cold_start_estimate_ms, etc.) which we ignore for now.
    struct ForgeModel: Codable, Sendable, Identifiable {
        let id: String
        let type: String?
        let provider: String?
        let status: String?
        let pickable: Bool?
        let canonicalId: String?
        /// Lifecycle metadata. Forge keeps deprecated models `pickable: true`
        /// through their deprecation window so existing pinned references
        /// (e.g. a saved Desk selection) keep working until the sweep date.
        /// We hide them from a fresh picker session because (a) they have a
        /// documented replacement and (b) deprecation is a strong signal the
        /// model has known issues — it's how an example deprecated
        /// model (`example-permissive`, replaced by a newer permissive
        /// model) revealed an intermittent system-prompt leak in production.
        let deprecatedUntil: String?
        let retiredOn: String?
        let replacedBy: String?

        enum CodingKeys: String, CodingKey {
            case id, type, provider, status, pickable
            case canonicalId = "canonical_id"
            case deprecatedUntil = "deprecated_until"
            case retiredOn = "retired_on"
            case replacedBy = "replaced_by"
        }

        /// True for picker entries the user should be able to select. Filters
        /// out deprecated, retired, and non-text/vlm models. Matches Desk's
        /// `lib/providers/forge.ts:listActiveModels` filter for parity.
        var isPickable: Bool {
            (pickable ?? false)
            && (status ?? "available") == "available"
            && deprecatedUntil == nil
            && retiredOn == nil
            && (type == nil || type == "text" || type == "vlm")
        }

        /// Local Forge models have provider == null; cloud passthrough models
        /// (e.g. claude-* via Anthropic) carry their provider name. Used to
        /// group the picker into Local vs Cloud sections.
        var isLocal: Bool { provider == nil || provider?.isEmpty == true }
    }

    struct ForgeModelsResponse: Codable, Sendable {
        let data: [ForgeModel]
    }

    /// Sends a chat exchange to Nexus's /v1/chat/aria endpoint and streams
    /// back named-event SSE that the parser maps into ChatEvent values.
    ///
    /// This is the same endpoint Desk talks to, which routes through
    /// runAgentTask('aria') — full agent with tools (Gmail, Calendar, GitHub,
    /// iMessage, etc.). Replaces the legacy /api/chat handler that called
    /// Forge LLM directly with no tool access.
    ///
    /// History persistence is server-side: Nexus inserts each user turn into
    /// channel_messages (channel='aria-direct'), shared with Desk and the
    /// iMessage relay. The phone, the laptop, and iMessage all converse with
    /// the same ARIA conversation thread.
    func sendMessage(messages: [ChatTurn], model: String? = nil, voiceMode: Bool = false) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    self.logger.logVerbose("api", "POST /v1/chat/aria (SSE) — \(messages.count) turns")
                    let url = try buildURL(path: "/v1/chat/aria")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    applyAuth(&request)

                    var body: [String: Any] = ["messages": messages.map { ["role": $0.role, "content": $0.content] }]
                    if let model, !model.isEmpty { body["model"] = model }
                    if voiceMode { body["voice_mode"] = true }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.yield(.error(message: "Invalid response"))
                        continuation.finish()
                        return
                    }
                    if http.statusCode == 401 {
                        self.logger.logMinimal("api", "SSE auth expired (401)")
                        self.emitTelemetry(path: "/v1/chat/aria", status: 401, kind: .auth)
                        continuation.yield(.error(message: "Session expired — please sign in again"))
                        continuation.finish()
                        return
                    }
                    if http.statusCode != 200 {
                        self.logger.logMinimal("api", "SSE error: HTTP \(http.statusCode)")
                        self.emitTelemetry(path: "/v1/chat/aria", status: http.statusCode, kind: http.statusCode >= 500 ? .http5xx : .http4xx)
                        continuation.yield(.error(message: "Server error (\(http.statusCode))"))
                        continuation.finish()
                        return
                    }

                    self.logger.logVerbose("api", "SSE stream connected")

                    // Nexus emits SSE blocks of the form:
                    //   event: <name>\n
                    //   data: <json>\n
                    //   \n
                    // (potentially multiple data: lines per block, joined by
                    // \n per the SSE spec). We trigger a flush on TWO signals:
                    //   1. an empty line — the canonical SSE block separator
                    //   2. a new `event:` line while a block is already pending
                    //      — defensive against AsyncLineSequence implementations
                    //      that may consolidate consecutive \n\n into a single
                    //      delimiter and skip the empty line entirely. Without
                    //      this the iOS chat displayed empty assistant bubbles
                    //      because the only flush ever happened at end-of-stream
                    //      (TestFlight build 108 incident, 2026-04-26).
                    var pendingEvent: String? = nil
                    var pendingData: [String] = []

                    func flushBlock() {
                        defer {
                            pendingEvent = nil
                            pendingData = []
                        }
                        let dataJoined = pendingData.joined(separator: "\n")
                        if dataJoined.isEmpty && pendingEvent == nil { return }
                        guard let event = ChatEvent.fromSSEBlock(eventName: pendingEvent, data: dataJoined) else {
                            self.logger.logDebug("api", "SSE event ignored:", pendingEvent ?? "(no name)", String(dataJoined.prefix(120)))
                            return
                        }
                        continuation.yield(event)
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty {
                            flushBlock()
                            continue
                        }
                        if line.hasPrefix(":") { continue }  // SSE comment
                        if line.hasPrefix("event:") {
                            // A new event boundary — flush any prior pending
                            // block (handles the no-empty-line case described
                            // above; harmless when an empty line already ran
                            // since flushBlock() short-circuits on empty state).
                            flushBlock()
                            pendingEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            pendingData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    // Flush a trailing block that didn't end with a blank line
                    flushBlock()

                    self.logger.logVerbose("api", "SSE stream finished")
                    continuation.finish()
                } catch {
                    self.logger.logMinimal("api", "SSE error:", error.localizedDescription)
                    self.emitTelemetry(path: "/v1/chat/aria", status: nil, kind: .network)
                    continuation.yield(.error(message: error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    /// Load the last `limit` messages from the aria-direct channel — same
    /// channel Desk's /aria thread reads from. Used by the iOS chat view on
    /// open to hydrate the thread with prior exchanges (server is the
    /// single source of truth post-Phase-5).
    func loadAriaHistory(limit: Int = 50) async throws -> [ChannelMessageDTO] {
        let response: ChannelHistoryResponse = try await get("/v1/channels/aria-direct/history?limit=\(limit)")
        return response.messages
    }

    /// Fetch the catalog of models Forge exposes — proxied by Nexus at
    /// /v1/forge/models which calls Forge's own /v1/models. Returns only
    /// pickable, available, text/vlm models. Used by the iOS ModelPicker
    /// in the sidebar (mirrors what Desk's /api/models endpoint serves).
    func listForgeModels() async throws -> [ForgeModel] {
        let response: ForgeModelsResponse = try await get("/v1/forge/models")
        return response.data.filter { $0.isPickable }
    }

    // MARK: - Generic helpers

    func get<T: Codable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET")
    }

    func request<T: Codable>(path: String, method: String, body: Data? = nil) async throws -> T {
        logger.logVerbose("api", "\(method) \(path)")
        let url = try buildURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        applyAuth(&req)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // Transport failure (offline / DNS / timeout) — report best-effort, then rethrow.
            emitTelemetry(path: path, status: nil, kind: .network)
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            logger.logMinimal("api", "Error: Invalid response for \(method) \(path)")
            emitTelemetry(path: path, status: nil, kind: .network)
            throw APIError.invalidResponse
        }

        logger.logVerbose("api", "Response \(http.statusCode) for \(method) \(path)")
        logger.logDebug("api", "Body:", String(data: data.prefix(500), encoding: .utf8) ?? "(non-UTF8)")

        if http.statusCode == 401 {
            logger.logMinimal("api", "Unauthorized for \(method) \(path)")
            emitTelemetry(path: path, status: 401, kind: .auth)
            throw APIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.logMinimal("api", "Server error \(http.statusCode) for \(method) \(path):", message.prefix(200))
            emitTelemetry(path: path, status: http.statusCode, kind: http.statusCode >= 500 ? .http5xx : .http4xx)
            throw APIError.serverError(statusCode: http.statusCode, message: message)
        }

        // Handle empty responses
        if data.isEmpty || http.statusCode == 204 {
            if let empty = EmptyResponse() as? T {
                return empty
            }
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // A 2xx the app cannot decode is a contract-drift failure — report it.
            emitTelemetry(path: path, status: http.statusCode, kind: .decode)
            throw error
        }
    }

    /// Fire-and-forget mobile-error telemetry (OB-52305). Never blocks the caller;
    /// the telemetry actor rate-limits and never reports its own route's failures.
    private func emitTelemetry(path: String, status: Int?, kind: MobileErrorTelemetry.FailureKind) {
        Task { await MobileErrorTelemetry.shared.record(path: path, status: status, failureKind: kind) }
    }

    func request<T: Codable>(path: String, method: String, body: Data? = nil, timeout: TimeInterval) async throws -> T {
        let url = try buildURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = timeout
        applyAuth(&req)

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: http.statusCode, message: message)
        }

        // Handle empty responses
        if data.isEmpty || http.statusCode == 204 {
            if let empty = EmptyResponse() as? T {
                return empty
            }
        }

        return try decoder.decode(T.self, from: data)
    }

    func buildURL(path: String) throws -> URL {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    func applyAuth(_ request: inout URLRequest) {
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

// MARK: - Supporting types

struct EmptyResponse: Codable {
    init() {}
}

struct TimingFeedbackAPIResponse: Codable {
    let saved: Bool
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case reviewConflict(ReviewCard)
    case noteRequired(prompt: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Server URL is not configured"
        case .invalidResponse: "Invalid response from server"
        case .unauthorized: "Session expired — please sign in again"
        case .serverError(let code, let msg): "Server error (\(code)): \(msg)"
        case .reviewConflict: "This card was already decided elsewhere"
        case .noteRequired(let prompt): prompt
        }
    }
}
