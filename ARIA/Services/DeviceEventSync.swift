import Foundation

/// Uploads the Shortcuts-automation event queue to POST /api/device-events.
/// Runs from the ingest intents (short budget), the SyncCoordinator sweep, app
/// foreground and the silent push. Failure handling follows MobileWriteContract:
/// offline/5xx/401 keep the queue; a 4xx on a batch halves the batch; a 4xx on a
/// single event dead-letters it.
@Observable
@MainActor
final class DeviceEventSync: BackgroundSyncable {
    static let shared = DeviceEventSync()

    enum BatchDecision: Equatable {
        case retry(size: Int)
        case deadLetterSingle
        case stop
    }

    static let maxBatch = 200

    private let logger = Logger.shared
    private let queue: DeviceEventQueue

    private(set) var isFlushing = false
    private(set) var pendingCount = 0
    private(set) var deadLetterCount = 0
    private(set) var stats: [DeviceEventQueueState.AutomationStat] = []
    var lastError: String?

    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "device_events_last_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "device_events_last_sync") }
    }

    init(queue: DeviceEventQueue = .shared) {
        self.queue = queue
    }

    // MARK: - BackgroundSyncable

    var sourceKey: String { "device_events" }
    /// A passive pipe: nothing to authorize. Which data flows is decided by the
    /// operator's Shortcuts automations, not by an in-app toggle.
    var isEnabled: Bool { true }

    func backgroundSync() async {
        await flush(budget: 10)
    }

    // MARK: - Upload

    static func nextBatchSize(current: Int, failure: WriteFailureCategory) -> BatchDecision {
        switch failure {
        case .validation where current > 1: return .retry(size: max(1, current / 2))
        case .validation: return .deadLetterSingle
        case .offline, .retryableServer, .unauthorized: return .stop
        }
    }

    func flush(budget: TimeInterval) async {
        guard !isFlushing else {
            logger.logVerbose("device-events", "Flush already running; event stays queued")
            return
        }
        guard let token = KeychainManager.getToken(), !token.isEmpty else {
            logger.logVerbose("device-events", "Flush skipped: not signed in")
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        let deadline = Date().addingTimeInterval(budget)
        var size = Self.maxBatch
        upload: while Date() < deadline {
            let batch = await queue.batch(limit: size)
            if batch.isEmpty { break }
            do {
                let ack = try await APIClient.shared.syncDeviceEvents(batch)
                await queue.apply(ack: ack, sent: batch)
                lastSyncDate = Date()
                lastError = nil
                size = Self.maxBatch
                logger.log("device-events", "Uploaded \(batch.count): \(ack.accepted.count) new, \(ack.duplicate.count) duplicate, \(ack.rejected.count) rejected")
            } catch {
                switch Self.nextBatchSize(current: batch.count, failure: error.writeFailureCategory) {
                case .retry(let newSize):
                    logger.logVerbose("device-events", "Batch of \(batch.count) refused; retrying with \(newSize)")
                    size = newSize
                case .deadLetterSingle:
                    await queue.deadLetter(batch, error: error.localizedDescription)
                case .stop:
                    lastError = error.localizedDescription
                    logger.logMinimal("device-events", "Upload paused:", error.localizedDescription)
                    break upload
                }
            }
        }
        await refreshSnapshot()
    }

    func refreshSnapshot() async {
        let snap = await queue.snapshot()
        pendingCount = snap.pending
        deadLetterCount = snap.deadLetters
        stats = snap.stats
    }

    func clearQueue() async {
        await queue.clear()
        await refreshSnapshot()
    }

    /// Enqueues a labelled test event and flushes it — the in-app proof
    /// that the Shortcuts ingest pipe works end to end (Settings →
    /// Automations). Returns a user-facing result string.
    func sendTestEvent() async -> String {
        let now = Date()
        let event = DeviceEventFactory.make(
            channel: .custom, automation: "Factotum test",
            body: "Factotum \(AppConfig.appVersion) (\(AppConfig.appBuild)) test event, sent from Settings → Automations.",
            fields: ["label": .string("factotum-test"), "app_version": .string(AppConfig.appVersion)],
            producedAt: now, capturedAt: now)
        await DeviceEventQueue.shared.enqueue(DeviceEventFactory.fitted(event))
        await flush(budget: 10)
        await refreshSnapshot()
        if let lastError {
            return "Queued, but the last upload reported: \(lastError)"
        }
        return pendingCount == 0
            ? "Sent — Nexus accepted the test event."
            : "Queued (\(pendingCount) pending) — it uploads on the next sweep."
    }

    #if DEBUG
    static func runSelfCheck() {
        assert(nextBatchSize(current: 200, failure: .validation) == .retry(size: 100))
        assert(nextBatchSize(current: 3, failure: .validation) == .retry(size: 1))
        assert(nextBatchSize(current: 1, failure: .validation) == .deadLetterSingle)
        assert(nextBatchSize(current: 50, failure: .offline) == .stop)
        assert(nextBatchSize(current: 50, failure: .retryableServer) == .stop)
        assert(nextBatchSize(current: 50, failure: .unauthorized) == .stop)
        // Halving always reaches a single-event decision (loop terminates).
        var n = 200, steps = 0
        while case .retry(let next) = nextBatchSize(current: n, failure: .validation) { n = next; steps += 1 }
        assert(n == 1 && steps <= 8)
    }
    #endif
}
