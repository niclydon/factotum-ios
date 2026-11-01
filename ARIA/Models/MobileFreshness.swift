import Foundation

/// `GET /api/mobile/freshness` — aggregate-only Nexus data freshness / degraded-state
/// status (OB-52302). No private content. Used by Settings / Sync Freshness to show
/// server-side truth alongside local `SyncFreshness` last-run timestamps.
struct MobileFreshness: Codable, Sendable, Equatable {
    let contractVersion: String
    let serverTime: String
    let sources: [Source]
    let summary: Summary
    let platform: Platform

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case serverTime = "server_time"
        case sources, summary, platform
    }

    struct Source: Codable, Sendable, Equatable, Identifiable {
        let sourceKey: String
        let appKey: String
        let displayLabel: String
        /// device_sync | surface | push
        let kind: String
        /// fresh | stale | error | empty | unknown | disabled
        let status: String
        let lastSeenAt: String?
        /// never | lt_6h | 6h_24h | 1d_3d | gt_3d
        let ageBucket: String
        let expectedCadenceHours: Double?
        /// Aggregate class token only (never free-text errors).
        let failureClass: String?
        /// ok | stale | error | empty | degraded | unknown
        let userFacingState: String

        var id: String { sourceKey }

        enum CodingKeys: String, CodingKey {
            case sourceKey = "source_key"
            case appKey = "app_key"
            case displayLabel = "display_label"
            case kind, status
            case lastSeenAt = "last_seen_at"
            case ageBucket = "age_bucket"
            case expectedCadenceHours = "expected_cadence_hours"
            case failureClass = "failure_class"
            case userFacingState = "user_facing_state"
        }

        var lastSeenDate: Date? { lastSeenAt?.iso8601Date }
    }

    struct Summary: Codable, Sendable, Equatable {
        let fresh: Int
        let stale: Int
        let error: Int
        let empty: Int
        let unknown: Int
        let disabled: Int
        /// ok | degraded | error
        let overall: String
    }

    struct Platform: Codable, Sendable, Equatable {
        /// ok | unreachable | unknown | skipped
        let bridgeHealth: String
        let workerQueue: WorkerQueue

        enum CodingKeys: String, CodingKey {
            case bridgeHealth = "bridge_health"
            case workerQueue = "worker_queue"
        }

        struct WorkerQueue: Codable, Sendable, Equatable {
            let pending: Int?
            /// ok | backlog | unknown
            let status: String
        }
    }

    /// Offline placeholder when the server has never been reached.
    static let offlineDefaults = MobileFreshness(
        contractVersion: "0.0.0",
        serverTime: "",
        sources: [],
        summary: Summary(fresh: 0, stale: 0, error: 0, empty: 0, unknown: 0, disabled: 0, overall: "unknown"),
        platform: Platform(
            bridgeHealth: "unknown",
            workerQueue: Platform.WorkerQueue(pending: nil, status: "unknown")
        )
    )
}
