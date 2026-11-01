import Foundation

/// The standard ARIA-iOS mobile-write contract: one place that defines how a
/// client-originated write to Nexus is keyed for idempotency, how its failures
/// are classified for retry, and how an offline replay queue must behave.
///
/// The per-endpoint contract table lives in `docs/mobile-write-contract.md`;
/// this file is its executable core. Before this existed, the offline-replay +
/// idempotency behavior was implemented ad hoc inside `CardStore` and nowhere
/// else, so every write endpoint behaved differently and a transient 5xx during
/// replay was silently dropped as if the decision were moot (OB-52304).
///
/// The backend side is already idempotent by contract and covered by tests:
///   - card decide/reply — CAS-idempotent on the `idempotency_key` in the
///     Matrix bridge (`decideRoute`/`framework` tests);
///   - device-sync writes — content-upsert idempotent server-side (a replayed
///     re-sync is counted as an idempotent conflict, not a duplicate row;
///     nexus `ios-healthkit` test).
/// So the client is free to replay a retry-safe write without creating dupes.
enum MobileWriteContract {

    /// Upper bound on offline-replay attempts for a single queued write before it
    /// is abandoned. Guards against a persistently-failing (5xx) endpoint pinning
    /// an item in the queue forever. Offline (no-connectivity) waits do not count
    /// against this — only server/transport *attempts* that actually reached a
    /// failing response do.
    static let maxReplayAttempts = 8

    // MARK: - Idempotency keys (client-supplied, stable per logical write)

    /// The card-decision idempotency key. Kept byte-identical to the convention
    /// already in flight (`"<cardId>:<action>"`) so replays of decisions queued
    /// by an older build still collapse onto the same server-side key — a safe
    /// migration, not a new keyspace.
    static func cardDecisionKey(cardId: String, action: String) -> String {
        "\(cardId):\(action)"
    }

    /// The general client idempotency key convention for a keyed write:
    /// `"<route>:<entity>"` or `"<route>:<entity>:<action>"`. Used when a new
    /// write endpoint opts into explicit idempotency; device-sync writes rely on
    /// server-side content-upsert instead and do not need a key.
    static func key(route: String, entity: String, action: String? = nil) -> String {
        if let action { return "\(route):\(entity):\(action)" }
        return "\(route):\(entity)"
    }

    #if DEBUG
    /// Compile- and launch-time characterization of the contract. There is no
    /// XCTest target in this repo (see `docs/aria-ios-nexus-release-verification.md`
    /// §4), so this `#if DEBUG` self-check is the app-side "automated test": it
    /// runs at debug launch and traps if the classification or key convention
    /// ever regresses. Cheap, deterministic, no network.
    static func runSelfCheck() {
        // Idempotency-key convention must not drift (replays of in-flight keys).
        assert(cardDecisionKey(cardId: "card-1", action: "approve") == "card-1:approve",
               "card decision idempotency key convention changed — in-flight replays would fork")
        assert(key(route: "reminder", entity: "r-9", action: "adopt") == "reminder:r-9:adopt")
        assert(key(route: "health", entity: "batch-7") == "health:batch-7")

        // Retry classification must distinguish offline / retryable / validation / auth.
        assert(URLError(.notConnectedToInternet).writeFailureCategory == .offline)
        assert(URLError(.timedOut).writeFailureCategory == .offline)
        assert(APIError.serverError(statusCode: 503, message: "x").writeFailureCategory == .retryableServer)
        assert(APIError.serverError(statusCode: 500, message: "x").writeFailureCategory == .retryableServer)
        assert(APIError.serverError(statusCode: 422, message: "x").writeFailureCategory == .validation)
        assert(APIError.serverError(statusCode: 404, message: "x").writeFailureCategory == .validation)
        assert(APIError.unauthorized.writeFailureCategory == .unauthorized)

        // Retry-safety derived from the category.
        assert(WriteFailureCategory.offline.shouldReplay)
        assert(WriteFailureCategory.retryableServer.shouldReplay)
        assert(!WriteFailureCategory.validation.shouldReplay)
        assert(!WriteFailureCategory.unauthorized.shouldDrop) // pause, don't drop, until re-auth
    }
    #endif
}

/// How a failed client-originated write should be treated by the offline replay
/// queue. This is the single classifier every write call-site shares, so
/// "offline network failure", "retryable server failure", "stale/moot/validation
/// failure", and "auth-expired" are handled identically everywhere.
enum WriteFailureCategory: Equatable, Sendable {
    /// Transport failure — no connectivity, DNS, or timeout. Queue and replay
    /// when connectivity returns. Does not consume a replay attempt.
    case offline
    /// A 5xx / malformed-response — a transient backend failure. The active write
    /// endpoints are idempotent, so replaying is safe; bounded by `maxReplayAttempts`.
    case retryableServer
    /// A 4xx (except 401) — the request is malformed, stale, or moot. Never
    /// replay: it would loop forever. Drop it (the user-facing action, if any,
    /// already surfaced a distinct error).
    case validation
    /// A 401 — the session lapsed. Do not drop the queued write; pause replay
    /// until the app re-authenticates, then resume.
    case unauthorized

    /// Whether the queue should keep the item and try again.
    var shouldReplay: Bool {
        switch self {
        case .offline, .retryableServer: return true
        case .validation, .unauthorized: return false
        }
    }

    /// Whether the queue should discard the item permanently. `unauthorized` is
    /// the one non-replay case that is NOT dropped — it waits for re-auth.
    var shouldDrop: Bool {
        switch self {
        case .validation: return true
        case .offline, .retryableServer, .unauthorized: return false
        }
    }
}

extension Error {
    /// Classify any thrown error into a `WriteFailureCategory`. Handles the app's
    /// `APIError`, raw `URLError` transport failures (which escape unwrapped from
    /// `URLSession`), and — conservatively — treats an unrecognized error as
    /// `validation` (drop) rather than looping the queue forever on something we
    /// cannot prove is retry-safe.
    var writeFailureCategory: WriteFailureCategory {
        if let api = self as? APIError {
            switch api {
            case .unauthorized: return .unauthorized
            case .invalidResponse: return .retryableServer
            case .invalidURL: return .validation
            case .serverError(let code, _): return code >= 500 ? .retryableServer : .validation
            // Review decisions are never queued for replay: 409 means someone else decided, 400 needs a note.
            case .reviewConflict, .noteRequired: return .validation
            }
        }
        if self is URLError { return .offline }
        return .validation
    }
}
