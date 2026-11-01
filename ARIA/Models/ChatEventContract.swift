import Foundation

/// Characterization of the app-facing chat SSE contract (OB-52236). Pins
/// `ChatEvent.fromSSEBlock` behavior across the normal and malformed streams the
/// app must survive, so a drift in the Nexus `/v1/chat/aria` event protocol (or
/// an accidental parser edit) is caught at debug launch. There is no XCTest
/// target in this repo (see docs/aria-ios-nexus-release-verification.md §4), so
/// this `#if DEBUG` self-check is the app-side test. The full wire contract +
/// Desk parity reference is documented in docs/chat-model-contract.md.
enum ChatEventContract {
    #if DEBUG
    static func runSelfCheck() {
        // ── Normal stream: the events the app renders ──────────
        // text.delta (new protocol) and its aliases → .chunk
        assertChunk(ChatEvent.fromSSEBlock(eventName: "text.delta", data: #"{"delta":"hi"}"#), "hi")
        assertChunk(ChatEvent.fromSSEBlock(eventName: "text-delta", data: #"{"delta":"a"}"#), "a")
        // legacy "text" field is still accepted
        assertChunk(ChatEvent.fromSSEBlock(eventName: "text.delta", data: #"{"text":"b"}"#), "b")
        // AI-SDK plain shape: no event name, type in the data payload
        assertChunk(ChatEvent.fromSSEBlock(eventName: nil, data: #"{"type":"text.delta","delta":"c"}"#), "c")

        // done carries the model metadata used for the assistant-bubble footer
        assertDone(ChatEvent.fromSSEBlock(eventName: "done", data: #"{"message_id":"m1","model":"example-model"}"#), "m1", "example-model")
        // done with no model → nil model (footer renders nothing), still terminal
        assertDone(ChatEvent.fromSSEBlock(eventName: "done", data: #"{"message_id":"m2"}"#), "m2", nil)

        // error surfaces a message; accepts message or error field
        assertError(ChatEvent.fromSSEBlock(eventName: "error", data: #"{"message":"boom"}"#), "boom")
        assertError(ChatEvent.fromSSEBlock(eventName: "error", data: #"{"error":"bad"}"#), "bad")

        // tool-call.start → status text; tool-call.result → clears status
        assertStatus(ChatEvent.fromSSEBlock(eventName: "tool-call.start", data: #"{"name":"gmail_search"}"#), "Using gmail_search…")
        assertStatus(ChatEvent.fromSSEBlock(eventName: "tool-call.result", data: #"{"id":"1"}"#), "")

        // reasoning.delta is intentionally dropped (no "thinking" surface yet)
        assertNil(ChatEvent.fromSSEBlock(eventName: "reasoning.delta", data: #"{"delta":"x"}"#))

        // ── Malformed / edge streams: must not crash or mis-render ──
        assertNil(ChatEvent.fromSSEBlock(eventName: "text.delta", data: #"{"delta":""}"#))   // empty delta → nil
        assertNil(ChatEvent.fromSSEBlock(eventName: "text.delta", data: "not json"))          // bad JSON → nil
        assertNil(ChatEvent.fromSSEBlock(eventName: "text.delta", data: ""))                  // empty data → nil
        assertNil(ChatEvent.fromSSEBlock(eventName: "bogus.event", data: #"{"delta":"x"}"#)) // unknown event → nil
        assertNil(ChatEvent.fromSSEBlock(eventName: nil, data: #"{"no":"type"}"#))            // no name, no type → nil
        // error with neither field still yields a non-empty fallback message
        assertError(ChatEvent.fromSSEBlock(eventName: "error", data: "{}"), "Unknown error")
    }

    // MARK: - Assertion helpers (ChatEvent is not Equatable)

    private static func assertChunk(_ e: ChatEvent?, _ expected: String) {
        if case let .chunk(text)? = e, text == expected { return }
        assertionFailure("expected .chunk(\(expected)), got \(String(describing: e))")
    }
    private static func assertDone(_ e: ChatEvent?, _ id: String, _ model: String?) {
        if case let .done(messageId, m)? = e, messageId == id, m == model { return }
        assertionFailure("expected .done(\(id),\(String(describing: model))), got \(String(describing: e))")
    }
    private static func assertError(_ e: ChatEvent?, _ msg: String) {
        if case let .error(message)? = e, message == msg { return }
        assertionFailure("expected .error(\(msg)), got \(String(describing: e))")
    }
    private static func assertStatus(_ e: ChatEvent?, _ text: String) {
        if case let .status(t)? = e, t == text { return }
        assertionFailure("expected .status(\(text)), got \(String(describing: e))")
    }
    private static func assertNil(_ e: ChatEvent?) {
        if e == nil { return }
        assertionFailure("expected nil, got \(String(describing: e))")
    }
    #endif
}
