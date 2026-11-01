import Foundation

/// Endpoint surface of APIClient, split from APIClient.swift in the
/// Factotum 4.0 foundation pass (same pattern as the HealthKitService
/// decomposition in 3.4). The transport core (session, SSE chat,
/// request pipeline) stays in APIClient.swift; everything here is a
/// thin typed wrapper over get/request.
extension APIClient {
    // MARK: - Conversations

    func listConversations() async throws -> [ConversationDTO] {
        let response: ConversationsResponse = try await get("/api/conversations")
        return response.conversations
    }

    func getMessages(conversationId: String) async throws -> [MessageDTO] {
        let response: MessagesResponse = try await get("/api/conversations/\(conversationId)")
        return response.messages
    }

    func deleteConversation(id: String) async throws {
        let _: EmptyResponse = try await request(path: "/api/conversations/\(id)", method: "DELETE")
    }

    // MARK: - Health Data

    func syncHealthData(records: [RawHealthSample]) async throws -> HealthSyncResponse {
        let body = try JSONEncoder().encode(HealthSyncRequest(records: records))
        return try await request(path: "/api/health-data", method: "POST", body: body)
    }

    // MARK: - Device events (Shortcuts ingest pipe)

    /// POST /api/device-events — a batch of ≤200 queued events. Per-item outcome in the ack.
    func syncDeviceEvents(_ events: [DeviceEvent]) async throws -> IngestAck {
        let body = try JSONEncoder().encode(DeviceEventBatchRequest(events: events))
        return try await request(path: "/api/device-events", method: "POST", body: body)
    }

    /// POST /api/health-files — live clinical records / ECGs / workout routes (≤50 objects).
    func syncHealthFiles(_ health: HealthFilesRequest) async throws -> IngestAck {
        let body = try JSONEncoder().encode(health)
        return try await request(path: "/api/health-files", method: "POST", body: body)
    }

    // MARK: - Apple Music

    func syncMusicData(request syncRequest: MusicSyncRequest) async throws -> MusicSyncResponse {
        let body = try JSONEncoder().encode(syncRequest)
        return try await request(path: "/api/device-music", method: "POST", body: body)
    }

    /// Fetches the latest Nexus DJ recommendation. Returns nil on HTTP 404
    /// ("no recent recommendation" — the agent hasn't run yet, or it's been
    /// >2h). Any other error throws.
    func fetchMusicRecommendation() async throws -> MusicRecommendation? {
        do {
            let rec: MusicRecommendation = try await request(
                path: "/api/music-recommendations/current",
                method: "GET"
            )
            return rec
        } catch APIError.serverError(let code, _) where code == 404 {
            return nil
        }
    }

    /// Confirms to the server that the iOS app materialized the recommendation
    /// into an Apple Music playlist. The optional `appleMusicURL` is the
    /// `music.apple.com/library/playlist/...` link; when present, the server
    /// edits the original Discord post to add an "Open in Apple Music" link.
    func confirmMusicRecommendation(id: String, appleMusicURL: String? = nil) async throws {
        let payload = MusicRecommendationConfirmRequest(apple_music_url: appleMusicURL)
        let body = try JSONEncoder().encode(payload)
        let _: MusicRecommendationConfirmResponse = try await request(
            path: "/api/music-recommendations/\(id)/confirm",
            method: "POST",
            body: body
        )
    }

    // MARK: - Location

    func syncLocation(location: LocationRecord) async throws -> LocationSyncResponse {
        let body = try JSONEncoder().encode(LocationSyncRequest(location: location))
        return try await request(path: "/api/device-location", method: "POST", body: body)
    }

    // MARK: - Visits (CLVisit)

    func syncVisit(visit: VisitRecord) async throws -> VisitSyncResponse {
        let body = try JSONEncoder().encode(VisitSyncRequest(visit: visit))
        return try await request(path: "/api/device-visits", method: "POST", body: body)
    }

    // MARK: - Motion & Activity

    func syncActivity(activity: ActivityRecord) async throws -> ActivitySyncResponse {
        let body = try JSONEncoder().encode(ActivitySyncRequest(activity: activity))
        return try await request(path: "/api/device-activity", method: "POST", body: body)
    }

    /// Bulk-sync activity records (e.g. 7-day CoreMotion backfill).
    func syncActivities(activities: [ActivityRecord]) async throws -> ActivityBulkSyncResponse {
        let body = try JSONEncoder().encode(ActivityBulkSyncRequest(activities: activities))
        return try await request(path: "/api/device-activity", method: "POST", body: body)
    }

    // MARK: - Push Notifications

    func registerDeviceToken(_ token: String, deviceName: String? = nil, isSandbox: Bool = false) async throws {
        struct Body: Codable { let device_token: String; let device_name: String?; let is_sandbox: Bool }
        let body = try JSONEncoder().encode(Body(device_token: token, device_name: deviceName, is_sandbox: isSandbox))
        let _: EmptyResponse = try await request(path: "/api/notifications/device-token", method: "POST", body: body)
    }

    func unregisterDeviceToken(_ token: String) async throws {
        struct Body: Codable { let device_token: String }
        let body = try JSONEncoder().encode(Body(device_token: token))
        let _: EmptyResponse = try await request(path: "/api/notifications/device-token", method: "DELETE", body: body)
    }

    // MARK: - Device registration (Factotum Phase 2)

    /// POST /api/device-registration — the phone introduces itself as a
    /// managed Factotum device. Server upserts by device_id. A 404 means
    /// the Nexus endpoint has not shipped yet; callers treat that as a
    /// first-class pending state, not an error.
    func registerDevice(_ payload: DeviceRegistrationPayload) async throws {
        let body = try JSONEncoder().encode(payload)
        let _: EmptyResponse = try await request(path: "/api/device-registration", method: "POST", body: body)
    }

    // MARK: - Command ask + mobile bootstrap/freshness

    func commandAsk(query: String) async throws -> CommandAskResponse {
        struct Body: Codable { let query: String }
        let body = try JSONEncoder().encode(Body(query: query))
        return try await request(path: "/api/command/ask", method: "POST", body: body)
    }

    /// Config-only mobile bootstrap/capabilities (OB-52301). Never blocks chat; callers
    /// should treat failures as soft (cached/default capabilities).
    func fetchMobileBootstrap() async throws -> MobileBootstrap {
        try await get("/api/mobile/bootstrap")
    }

    /// Aggregate-only data freshness / degraded-state status (OB-52302). Soft-fail at call sites;
    /// never overwrites local SyncFreshness last-run timestamps.
    func fetchMobileFreshness() async throws -> MobileFreshness {
        try await get("/api/mobile/freshness")
    }

    /// Aggregate-only estate snapshot over the factotum_* tables (OB-66209).
    func fetchMobileEstate() async throws -> MobileEstate {
        try await get("/api/mobile/estate")
    }

    /// One Big Thing composites (Factotum 4.0 W3, OB-66557).
    func getOneBigThing() async throws -> MobileOneBigThing {
        try await get("/api/mobile/one-big-thing")
    }

    /// POST /api/mobile/photo-intelligence (Factotum 4.0 W9 Lens, OB-66559):
    /// uploads a batch of DERIVED photo/video records only. Originals never
    /// leave the device; the server enforces a strict field allowlist.
    func postPhotoIntelligence(_ batch: PhotoIntelligenceBatchRequest) async throws -> PhotoIntelligenceResponse {
        let body = try JSONEncoder().encode(batch)
        return try await request(path: "/api/mobile/photo-intelligence", method: "POST", body: body)
    }

    /// POST /api/mobile/photo-intelligence/enrich (Factotum 4.1,
    /// OB-68202): bridge metadata (filename, pixel dimensions)
    /// for records the server already holds from pre-v2 builds.
    /// The server updates every stored row for each asset id.
    func postPhotoIntelligenceEnrich(_ batch: PhotoIntelligenceEnrichBatchRequest) async throws -> PhotoIntelligenceEnrichResponse {
        let body = try JSONEncoder().encode(batch)
        return try await request(path: "/api/mobile/photo-intelligence/enrich", method: "POST", body: body)
    }

    /// POST /api/mobile/photo-terms (photo text index prototype,
    /// OB-66960): tokenized Vision OCR terms per asset, landed in
    /// factotum_photo_terms (sibling of the Mac leo mirror).
    func postPhotoTerms(_ batch: PhotoTermsBatchRequest) async throws -> PhotoTermsResponse {
        let body = try JSONEncoder().encode(batch)
        return try await request(path: "/api/mobile/photo-terms", method: "POST", body: body)
    }

    /// GET /api/mobile/replay/day (Factotum 4.0 W1, OB-66560): one day's
    /// evidence pack across seven families, every item citable by id.
    func getReplayDay(date: String) async throws -> ReplayDayPack {
        try await get("/api/mobile/replay/day?date=\(date)")
    }

    /// POST /api/mobile/replay/ask (Factotum 4.0 W1, OB-66560): a narrative
    /// over a range of day packs whose factual claims cite pack items;
    /// citations arrive resolved to full items, unresolved ids are listed.
    func postReplayAsk(question: String, from: String, to: String) async throws -> ReplayAskResponse {
        let body = try JSONEncoder().encode(ReplayAskRequest(question: question, range: .init(from: from, to: to)))
        return try await request(path: "/api/mobile/replay/ask", method: "POST", body: body)
    }

    /// Per-host estate detail (upgrades-scan item 4, 3.4.0): the rows
    /// behind the aggregates — apps, packages (outdated first), services,
    /// recent actions for one registry host.
    func fetchEstateHostDetail(host: String) async throws -> MobileEstateHostDetail {
        try await get("/api/mobile/estate/hosts/\(host)")
    }

    // MARK: - Review cards (spec 2026-09-06 §1)

    func getReviewCards(status: ReviewListStatus) async throws -> ReviewCardsResponse {
        try await get("/api/mobile/review-cards?status=\(status.rawValue)")
    }

    /// Decide a card. Maps the server's 409 (decided on another surface) and 400 note_required
    /// into typed errors so the view can render a receipt / focus the note field.
    func decideReviewCard(id: String, decision: String, note: String?, selectedValues: [String]) async throws -> ReviewCard {
        struct Body: Codable { let decision: String; let note: String?; let selected_values: [String] }
        let body = try JSONEncoder().encode(Body(decision: decision, note: note, selected_values: selectedValues))
        do {
            let resp: ReviewDecideResponse = try await request(path: "/api/mobile/review-cards/\(id)/decide", method: "POST", body: body)
            return resp.card
        } catch APIError.serverError(let code, let message) {
            let data = Data(message.utf8)
            if code == 409, let conflict = try? decoder.decode(ReviewDecideConflict.self, from: data) {
                throw APIError.reviewConflict(conflict.card)
            }
            if code == 400, let rejected = try? decoder.decode(ReviewDecideRejected.self, from: data),
               rejected.error == "note_required" {
                throw APIError.noteRequired(prompt: rejected.prompt ?? "Add a note to continue")
            }
            throw APIError.serverError(statusCode: code, message: message)
        }
    }
    // MARK: - Today (read-only /v1 routes; mobile JWT accepted)

    func getSleepNightly(days: Int = 14) async throws -> SleepNightlyProfile { try await get("/v1/health/sleep/nightly?days=\(days)") }
    func getSleepRecovery(days: Int = 14) async throws -> SleepRecoveryProfile { try await get("/v1/health/sleep/recovery?days=\(days)") }
    func getActivityDaily(days: Int = 30) async throws -> ActivityDailyProfile {
        try await get("/v1/health/activity/daily?days=\(days)&metrics=steps,exercise_minutes,active_calories")
    }
    func getWorkouts(limit: Int = 10) async throws -> WorkoutsResponse { try await get("/v1/health/activity/workouts?limit=\(limit)") }
    func getVisits(limit: Int = 50) async throws -> VisitsResponse { try await get("/v1/location/visits?limit=\(limit)") }
    func getTimelineEvents(from: String, to: String, limit: Int = 20) async throws -> TimelineEventsResponse {
        try await get("/v1/timeline/events?from=\(from)&to=\(to)&limit=\(limit)")
    }

    /// Send a reply from a notification action. Fire-and-forget — doesn't consume the SSE stream.
    func sendReplyFromNotification(conversationId: String?, content: String) async throws {
        let url = try buildURL(path: "/api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)

        var bodyDict: [String: Any] = ["content": content]
        if let conversationId { bodyDict["conversationId"] = conversationId }
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        // Just wait for the connection to establish, don't consume the full SSE stream
        let _ = try await session.data(for: req)
    }

}
