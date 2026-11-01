import Foundation

/// An activity state record to sync to the ARIA server.
struct ActivityRecord: Codable, Sendable {
    let timestamp: String
    let stationary: Bool
    let walking: Bool
    let running: Bool
    let cycling: Bool
    let automotive: Bool
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case stationary
        case walking
        case running
        case cycling
        case automotive
        case confidence
    }
}

/// Wrapper for the activity sync request body.
struct ActivitySyncRequest: Codable, Sendable {
    let activity: ActivityRecord
}

/// Wrapper for bulk activity sync (backfill).
struct ActivityBulkSyncRequest: Codable, Sendable {
    let activities: [ActivityRecord]
}

/// Response from POST /api/device-activity.
struct ActivitySyncResponse: Codable, Sendable {
    let saved: Bool
}

/// Response from POST /api/device-activity (bulk).
struct ActivityBulkSyncResponse: Codable, Sendable {
    let saved: Int
    let total: Int
    let valid: Int
}
