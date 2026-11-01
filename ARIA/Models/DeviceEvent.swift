import Foundation

/// Any JSON value — the open `fields` object of a device event (device_events.event.v1).
/// (Distinct from ProactiveModels' scalar-only `JSONValue`.)
enum EventJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EventJSON])
    case object([String: EventJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([EventJSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: EventJSON].self) { self = .object(o) }
        else {
            throw DecodingError.typeMismatch(EventJSON.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Parse JSON text (object, array or scalar); nil when the text is not JSON.
    static func parse(_ text: String) -> EventJSON? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EventJSON.self, from: data)
    }
}

/// The six channels Nexus accepts for `device_events.event.v1` (see nexus payload_schemas).
enum DeviceEventChannel: String, Codable, Sendable, CaseIterable {
    case notification, transaction, app, device, custom, healthkit
}

struct DeviceEventApp: Codable, Sendable, Equatable {
    let name: String?
    let bundleId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case bundleId = "bundle_id"
    }
}

struct DeviceEventPayload: Codable, Sendable, Equatable {
    let kind: String
    let channel: DeviceEventChannel
    let app: DeviceEventApp?
    let title: String?
    let subtitle: String?
    let body: String?
    let fields: [String: EventJSON]
    let automation: String
}

/// One event from a Shortcuts automation (or ARIA itself), queued on the phone and
/// POSTed in batches to /api/device-events. `id` is the idempotency key.
struct DeviceEvent: Codable, Sendable, Equatable, Identifiable {
    static let kind = "device_events.event.v1"

    let id: String
    let producedAt: String
    let capturedAt: String?
    let payload: DeviceEventPayload

    enum CodingKeys: String, CodingKey {
        case id
        case producedAt = "produced_at"
        case capturedAt = "captured_at"
        case payload
    }
}

struct DeviceEventBatchRequest: Codable, Sendable {
    let events: [DeviceEvent]
}

/// Response of POST /api/device-events and POST /api/health-files.
struct IngestAck: Codable, Sendable, Equatable {
    struct Rejection: Codable, Sendable, Equatable {
        let id: String?
        let error: String
    }

    let accepted: [String]
    let duplicate: [String]
    let rejected: [Rejection]
}

/// Builds well-formed, size-bounded device events. All clipping counts Unicode
/// scalars — the unit the server's JSON Schema `maxLength` counts.
enum DeviceEventFactory {
    static let maxTitleScalars = 512
    static let maxBodyScalars = 8192
    static let maxAutomationScalars = 128
    static let maxJSONTextBytes = 16_384
    static let maxEventBytes = 30_000

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func clip(_ s: String?, _ max: Int) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        guard t.unicodeScalars.count > max else { return t }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: t.unicodeScalars.prefix(max))
        return String(view)
    }

    static func make(
        channel: DeviceEventChannel,
        automation: String,
        app: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        fields: [String: EventJSON] = [:],
        producedAt: Date,
        capturedAt: Date,
        id: UUID = UUID()
    ) -> DeviceEvent {
        DeviceEvent(
            id: id.uuidString.lowercased(),
            producedAt: iso.string(from: producedAt),
            capturedAt: iso.string(from: capturedAt),
            payload: DeviceEventPayload(
                kind: DeviceEvent.kind,
                channel: channel,
                app: clip(app, 256).map { DeviceEventApp(name: $0, bundleId: nil) },
                title: clip(title, maxTitleScalars),
                subtitle: clip(subtitle, maxTitleScalars),
                body: clip(body, maxBodyScalars),
                fields: fields,
                automation: clip(automation, maxAutomationScalars) ?? "unlabeled"
            )
        )
    }

    /// The "JSON" parameter of Log Event: valid JSON → `fields.json`, otherwise the
    /// clipped text → `fields.json_text` (so Nexus only treats real JSON as structured).
    static func jsonFields(_ text: String?) -> [String: EventJSON] {
        guard let text, !text.isEmpty else { return [:] }
        if text.utf8.count <= maxJSONTextBytes, let v = EventJSON.parse(text) { return ["json": v] }
        return ["json_text": .string(clip(text, maxBodyScalars) ?? "")]
    }

    static func encodedSize(_ e: DeviceEvent) -> Int {
        (try? JSONEncoder().encode(e).count) ?? Int.max
    }

    /// Guarantee the encoded event fits the server cap: drop the structured fields
    /// first, then shrink the body.
    static func fitted(_ e: DeviceEvent) -> DeviceEvent {
        if encodedSize(e) <= maxEventBytes { return e }
        let p = e.payload
        var slim = DeviceEvent(id: e.id, producedAt: e.producedAt, capturedAt: e.capturedAt, payload: DeviceEventPayload(
            kind: p.kind, channel: p.channel, app: p.app, title: p.title, subtitle: p.subtitle, body: p.body,
            fields: ["truncated": .bool(true)], automation: p.automation))
        if encodedSize(slim) <= maxEventBytes { return slim }
        slim = DeviceEvent(id: e.id, producedAt: e.producedAt, capturedAt: e.capturedAt, payload: DeviceEventPayload(
            kind: p.kind, channel: p.channel, app: p.app, title: p.title, subtitle: p.subtitle,
            body: clip(p.body, 2000), fields: ["truncated": .bool(true)], automation: p.automation))
        return slim
    }

    static func string(from date: Date) -> String { iso.string(from: date) }

    #if DEBUG
    static func runSelfCheck() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let fixed = UUID(uuidString: "0B6F3C0E-1F5E-4D7E-9A8B-2C3D4E5F6A7B")!
        let e = make(channel: .transaction, automation: "Wallet taps", app: "Wallet",
                     fields: ["merchant": .string("Blue Bottle"), "amount": .string("$6.25")],
                     producedAt: now, capturedAt: now, id: fixed)
        assert(e.id == "0b6f3c0e-1f5e-4d7e-9a8b-2c3d4e5f6a7b", "ids are lowercase UUIDs")
        let json = String(data: try! JSONEncoder().encode(e), encoding: .utf8)!
        assert(json.contains("\"produced_at\"") && json.contains("\"captured_at\""), "snake_case envelope keys")
        assert(json.contains("\"device_events.event.v1\"") && json.contains("\"transaction\""), "kind + channel raw values")
        assert(!json.contains("\"title\""), "nil optionals are omitted, not null")
        let roundTrip = try! JSONDecoder().decode(DeviceEvent.self, from: json.data(using: .utf8)!)
        assert(roundTrip == e, "Codable round-trip")

        // Clipping counts scalars; emoji + combining marks at the limit stay within it.
        let accented = String(repeating: "e\u{0301}", count: 400)   // 800 scalars
        assert(clip(accented, 512)!.unicodeScalars.count == 512)
        assert(clip("   ", 10) == nil)
        assert(make(channel: .custom, automation: "  ", producedAt: now, capturedAt: now).payload.automation == "unlabeled")
        let emojiBody = String(repeating: "👩‍👩‍👧‍👦", count: 3000)
        let clipped = make(channel: .notification, automation: "x", body: emojiBody, producedAt: now, capturedAt: now)
        assert(clipped.payload.body!.unicodeScalars.count == maxBodyScalars)

        // JSON parameter handling.
        assert(jsonFields("{\"a\":1}") == ["json": .object(["a": .number(1)])])
        assert(jsonFields("not json") == ["json_text": .string("not json")])
        assert(jsonFields(nil).isEmpty)

        // Size fitting.
        let big = make(channel: .custom, automation: "x",
                       fields: ["json": .string(String(repeating: "a", count: 40_000))],
                       producedAt: now, capturedAt: now)
        assert(encodedSize(fitted(big)) <= maxEventBytes, "fitted event must fit the server cap")
        assert(encodedSize(fitted(clipped)) <= maxEventBytes)
    }
    #endif
}
