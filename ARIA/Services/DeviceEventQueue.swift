import Foundation

/// Pure queue logic for Shortcuts-automation events. Value type so the DEBUG
/// self-check can exercise every rule synchronously; `DeviceEventQueue` (below)
/// adds persistence and serialization.
struct DeviceEventQueueState: Codable, Sendable, Equatable {
    struct QueuedEvent: Codable, Sendable, Equatable {
        let event: DeviceEvent
        let enqueuedAt: Date
    }

    struct DeadLetter: Codable, Sendable, Equatable {
        let event: DeviceEvent
        let error: String
        let at: Date
    }

    struct AutomationLog: Codable, Sendable, Equatable {
        var channel: DeviceEventChannel
        var recent: [Date]
    }

    struct AutomationStat: Sendable, Equatable, Identifiable {
        let automation: String
        let channel: DeviceEventChannel
        let lastAt: Date?
        let count24h: Int
        let quiet: Bool
        var id: String { automation }
    }

    static let maxPending = 5000
    static let maxAge: TimeInterval = 7 * 86_400
    static let maxDeadLetters = 200
    static let maxRecentPerAutomation = 50
    static let internalPrefix = "aria:"

    var pending: [QueuedEvent] = []
    var deadLetters: [DeadLetter] = []
    var sentLog: [String: AutomationLog] = [:]
    var droppedSinceLastReport = 0

    mutating func enqueue(_ event: DeviceEvent, now: Date, maxPending: Int = Self.maxPending, maxAge: TimeInterval = Self.maxAge) {
        pending.append(QueuedEvent(event: event, enqueuedAt: now))
        prune(now: now, maxPending: maxPending, maxAge: maxAge)
        if droppedSinceLastReport > 0 {
            let dropped = droppedSinceLastReport
            droppedSinceLastReport = 0
            pending.append(QueuedEvent(event: DeviceEventFactory.make(
                channel: .device, automation: "aria:queue", title: "queue overflow",
                fields: ["kind": .string("queue_overflow"), "dropped": .number(Double(dropped))],
                producedAt: now, capturedAt: now), enqueuedAt: now))
            // Route through prune() again (not a raw trim) so a drop caused by
            // appending the overflow-report event itself is still counted
            // toward the NEXT report — a raw trim here would reset-then-drop
            // silently, with no future report ever reflecting it.
            prune(now: now, maxPending: maxPending, maxAge: maxAge)
        }
    }

    private mutating func prune(now: Date, maxPending: Int, maxAge: TimeInterval) {
        let before = pending.count
        pending.removeAll { now.timeIntervalSince($0.enqueuedAt) > maxAge }
        if pending.count > maxPending { pending.removeFirst(pending.count - maxPending) }
        droppedSinceLastReport += before - pending.count
    }

    func batch(limit: Int) -> [DeviceEvent] {
        pending.prefix(max(0, limit)).map(\.event)
    }

    /// Settle a sent batch against Nexus's ack. accepted/duplicate → done (logged);
    /// rejected-by-id → dead letter; anything sent but unmentioned (e.g. a rejection
    /// whose id Nexus could not read) → dead letter, so nothing retries forever.
    mutating func apply(ack: IngestAck, sent: [DeviceEvent], now: Date) {
        let done = Set(ack.accepted + ack.duplicate)
        var rejectedById: [String: String] = [:]
        for r in ack.rejected { if let id = r.id, rejectedById[id] == nil { rejectedById[id] = r.error } }
        let fallbackError = ack.rejected.first { $0.id == nil }?.error ?? "not acknowledged"

        var removed = Set<String>()
        for e in sent {
            if done.contains(e.id) {
                let at = pending.first { $0.event.id == e.id }?.enqueuedAt ?? now
                record(e, at: at)
            } else {
                appendDeadLetter(e, error: rejectedById[e.id] ?? fallbackError, now: now)
            }
            removed.insert(e.id)
        }
        pending.removeAll { removed.contains($0.event.id) }
    }

    mutating func deadLetter(_ events: [DeviceEvent], error: String, now: Date) {
        let ids = Set(events.map(\.id))
        for e in events { appendDeadLetter(e, error: error, now: now) }
        pending.removeAll { ids.contains($0.event.id) }
    }

    private mutating func appendDeadLetter(_ e: DeviceEvent, error: String, now: Date) {
        deadLetters.append(DeadLetter(event: e, error: String(error.prefix(300)), at: now))
        if deadLetters.count > Self.maxDeadLetters { deadLetters.removeFirst(deadLetters.count - Self.maxDeadLetters) }
    }

    private mutating func record(_ e: DeviceEvent, at: Date) {
        var log = sentLog[e.payload.automation] ?? AutomationLog(channel: e.payload.channel, recent: [])
        log.channel = e.payload.channel
        log.recent.append(at)
        log.recent.sort()
        if log.recent.count > Self.maxRecentPerAutomation { log.recent.removeFirst(log.recent.count - Self.maxRecentPerAutomation) }
        sentLog[e.payload.automation] = log
    }

    func automationStats(now: Date) -> [AutomationStat] {
        sentLog
            .filter { !$0.key.hasPrefix(Self.internalPrefix) }
            .map { key, log in
                AutomationStat(
                    automation: key,
                    channel: log.channel,
                    lastAt: log.recent.last,
                    count24h: log.recent.filter { now.timeIntervalSince($0) <= 86_400 }.count,
                    quiet: Self.isQuiet(log.recent, now: now))
            }
            .sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
    }

    /// Mirrors Nexus's stale rule: ≥5 sends and silence > max(3 × median gap, 48 h).
    static func isQuiet(_ times: [Date], now: Date) -> Bool {
        guard times.count >= 5, let last = times.last else { return false }
        let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }.sorted()
        let median = gaps.count % 2 == 1 ? gaps[gaps.count / 2] : (gaps[gaps.count / 2 - 1] + gaps[gaps.count / 2]) / 2
        return now.timeIntervalSince(last) > max(3 * median, 48 * 3600)
    }

    #if DEBUG
    static func runSelfCheck() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        func ev(_ label: String, _ at: Date) -> DeviceEvent {
            DeviceEventFactory.make(channel: .notification, automation: label, title: "t", producedAt: at, capturedAt: at)
        }

        // Upload settles accepted, duplicate, rejected-by-id and null-id rejections.
        var s = DeviceEventQueueState()
        let a = ev("Uber", t0), b = ev("Uber", t0), c = ev("Bank", t0), d = ev("Bank", t0)
        for e in [a, b, c, d] { s.enqueue(e, now: t0) }
        assert(s.batch(limit: 2).map(\.id) == [a.id, b.id], "FIFO batches")
        s.apply(ack: IngestAck(accepted: [a.id], duplicate: [b.id],
                               rejected: [.init(id: c.id, error: "schema_violation"), .init(id: nil, error: "id must be a UUID")]),
                sent: [a, b, c, d], now: t0)
        assert(s.pending.isEmpty, "every sent event is settled")
        assert(s.deadLetters.map(\.event.id) == [c.id, d.id], "rejected + unacknowledged are dead-lettered")
        assert(s.deadLetters[1].error == "id must be a UUID", "null-id rejection error is kept")
        assert(s.sentLog["Uber"]?.recent.count == 2 && s.sentLog["Bank"] == nil)

        // A partial batch leaves the rest queued (second concurrent flush case).
        var p = DeviceEventQueueState()
        let e1 = ev("x", t0), e2 = ev("x", t0)
        p.enqueue(e1, now: t0); p.enqueue(e2, now: t0)
        p.apply(ack: IngestAck(accepted: [e1.id], duplicate: [], rejected: []), sent: [e1], now: t0)
        assert(p.pending.map(\.event.id) == [e2.id])

        // Overflow drops oldest and reports it once.
        var o = DeviceEventQueueState()
        for i in 0..<5 { o.enqueue(ev("x", t0.addingTimeInterval(Double(i))), now: t0, maxPending: 3, maxAge: maxAge) }
        assert(o.pending.count == 3)
        assert(o.pending.contains { $0.event.payload.automation == "aria:queue" }, "overflow event enqueued")
        // Not asserting droppedSinceLastReport == 0 here: with 5 pushes into a
        // maxPending-3 queue, the LAST call's own overflow-report append can
        // itself overflow (see the deterministic case below), legitimately
        // leaving a drop counted-but-not-yet-reported until the next enqueue.

        // The overflow-report event's own append can itself overflow the queue
        // (a second trim inline in enqueue). That second trim must go through
        // the same accounting as every other drop, so the event it silently
        // removes is still counted toward the NEXT overflow report — never
        // reset to 0 and then dropped with no trace.
        var ov = DeviceEventQueueState()
        ov.enqueue(ev("a", t0), now: t0, maxPending: 3, maxAge: maxAge)
        ov.enqueue(ev("b", t0), now: t0, maxPending: 3, maxAge: maxAge)
        ov.enqueue(ev("c", t0), now: t0, maxPending: 3, maxAge: maxAge)
        // Queue is now exactly full ([a,b,c], no drops yet). This next enqueue
        // triggers prune's trim (drops "a", reports it) AND, because appending
        // the overflow-report event itself overflows the now-full queue, a
        // second trim (drops "b") that must not be reported as zero.
        ov.enqueue(ev("d", t0), now: t0, maxPending: 3, maxAge: maxAge)
        assert(!ov.pending.contains { $0.event.payload.automation == "b" }, "'b' must actually be dropped by the second trim")
        assert(ov.droppedSinceLastReport > 0, "the second trim's drop must still be counted toward the next overflow report")

        // Age pruning.
        var g = DeviceEventQueueState()
        g.enqueue(ev("old", t0), now: t0)
        g.enqueue(ev("new", t0), now: t0.addingTimeInterval(8 * 86_400))
        assert(!g.pending.contains { $0.event.payload.automation == "old" })

        // Quiet rule.
        let daily = (0..<6).map { t0.addingTimeInterval(Double($0) * 86_400) }
        assert(isQuiet(daily, now: daily.last!.addingTimeInterval(4 * 86_400)))
        assert(!isQuiet(daily, now: daily.last!.addingTimeInterval(2 * 86_400)))
        assert(!isQuiet(Array(daily.prefix(4)), now: t0.addingTimeInterval(100 * 86_400)), "needs ≥5 sends")
        assert(DeviceEventQueueState(sentLog: ["aria:queue": .init(channel: .device, recent: daily)]).automationStats(now: t0).isEmpty,
               "internal labels are hidden")

        // Persistence failure must not crash (first-unlock data protection case).
        let q = DeviceEventQueue(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        Task { await q.enqueue(ev("x", t0)); let snap = await q.snapshot(now: t0); assert(snap.pending == 1, "kept in memory") }
    }
    #endif
}

struct DeviceEventQueueSnapshot: Sendable {
    let pending: Int
    let deadLetters: Int
    let stats: [DeviceEventQueueState.AutomationStat]
}

/// Serializes queue mutations and persists them as one JSON file in the App Group
/// container (falls back to Application Support when the group is unavailable,
/// e.g. unsigned simulator builds). A failed write keeps the state in memory and
/// is logged; it never throws to the caller (App Intents must always succeed).
actor DeviceEventQueue {
    static let shared = DeviceEventQueue(directory: DeviceEventQueue.defaultDirectory())

    private let fileURL: URL
    private var state: DeviceEventQueueState
    private let logger = Logger.shared

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("device-event-queue.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(DeviceEventQueueState.self, from: data) {
            state = decoded
        } else {
            state = DeviceEventQueueState()
        }
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.factotum")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DeviceEvents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func enqueue(_ event: DeviceEvent, now: Date = Date()) {
        state.enqueue(event, now: now)
        logger.logVerbose("device-events", "Queued \(event.payload.channel.rawValue) from '\(event.payload.automation)' (depth \(state.pending.count))")
        persist()
    }

    func batch(limit: Int) -> [DeviceEvent] { state.batch(limit: limit) }

    func apply(ack: IngestAck, sent: [DeviceEvent], now: Date = Date()) {
        state.apply(ack: ack, sent: sent, now: now)
        persist()
    }

    func deadLetter(_ events: [DeviceEvent], error: String, now: Date = Date()) {
        state.deadLetter(events, error: error, now: now)
        logger.logMinimal("device-events", "Dead-lettered \(events.count) event(s):", error.prefix(200))
        persist()
    }

    func snapshot(now: Date = Date()) -> DeviceEventQueueSnapshot {
        DeviceEventQueueSnapshot(pending: state.pending.count, deadLetters: state.deadLetters.count, stats: state.automationStats(now: now))
    }

    func clear() {
        state = DeviceEventQueueState()
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.logMinimal("device-events", "Queue persist failed (kept in memory):", error.localizedDescription)
        }
    }
}
