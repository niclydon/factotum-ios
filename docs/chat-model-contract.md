# Chat + Model-Picker Contract (desktop parity)

The chat/model cross-surface contract, made explicit: the iOS app
decodes the same backend chat SSE stream, channel history, and model
catalog that the backend's desktop client relies on. The parser is
pinned by `ARIA/Models/ChatEventContract.swift` (a `#if DEBUG`
characterization) and by the fixtures in `fixtures/mobile-api.v1/`.

## SSE event contract (`POST /v1/chat/aria`)

The backend streams named-event SSE frames —
`event: <name>\ndata: <json>\n\n`. The iOS parser
(`ChatEvent.fromSSEBlock`) maps them into the UI-facing `ChatEvent`
enum:

| Wire event | Payload | → `ChatEvent` | Notes |
|---|---|---|---|
| `text.delta` (`text-delta`, `chunk`) | `{delta}` or legacy `{text}` | `.chunk(text)` | empty delta → dropped (nil) |
| `reasoning.delta` (`reasoning-delta`) | `{delta}` | *dropped (nil)* | no "thinking" surface yet |
| `tool-call.start` (`tool-call-start`, `tool.call.start`) | `{id,name,args}` | `.status("Using <name>…")` | flattened to status text |
| `tool-call.result` (`tool-call-result`, `tool.call.result`) | `{id,output}` | `.status("")` | clears the status line |
| `done` (`finish`) | `{message_id?, model?, usage?}` | `.done(messageId, model)` | `model` → grey footer under the bubble (may be nil) |
| `error` | `{message}` or `{error}` | `.error(message)` | falls back to "Unknown error" |
| `start` / `status` / `photos` | — | `.start` / `.status` / `.photos` | **legacy** `/api/chat` events; `/v1/chat/aria` does not emit `start` |

**Robustness the parser guarantees** (pinned in
`ChatEventContract.runSelfCheck`): accepts either the
`event: <name>` framing *or* a plain `data:{type:...}` payload (the
AI-SDK adapter shape, matching the desktop client's transport);
tolerates newline coalescing in the byte stream; and returns `nil`
(ignored, logged at debug) for bad JSON, empty data, empty delta, and
unknown events rather than crashing or rendering an empty bubble.

## History (`GET /v1/channels/aria-direct/history`)

iOS is single-thread: chat, the desktop client, and any message relays
share one assistant channel thread. `loadAriaHistory(limit:)` hydrates
it from the same server-side rows the desktop reads, so message
order/content match across surfaces — no per-conversation list, no
duplicate/missing turns. The user turn is persisted server-side by the
chat route before streaming, so history is the single source of truth
after a send. Message roles are derived from `sender_id`: the human's
configured sender id (in this export's example fixtures, `"user"`)
maps to `user`; anything else maps to `assistant`.

## Model picker (`GET /v1/forge/models`) — desktop parity

`APIClient.listForgeModels()` returns `data.filter { $0.isPickable }`.
`ForgeModel.isPickable` mirrors the desktop client's active-model
filter:

| Rule | iOS `isPickable` | Desktop filter |
|---|---|---|
| pickable | `pickable ?? false` | `pickable !== false` |
| not deprecated | `deprecatedUntil == nil` | `!deprecated_until` |
| not retired | `retiredOn == nil` | `!retired_on` |
| available status | `status == "available"` | (trusts lifecycle fields) |
| text/vlm only | `type ∈ {nil, text, vlm}` | (picker context) |

The iOS picker additionally requires `status == available` and a
text/vlm `type` (it must not offer an embedding/rerank model as a chat
model). Grouping mirrors the desktop picker: a **"Server default"**
row (selects `nil`), a **local models** section (`isLocal` —
`provider == nil`), and a **cloud passthrough** section (provider name
as hint). Deprecated models stay `pickable:true` through their window
server-side but are hidden from a fresh picker session — the lesson of
an example deprecated model (`example-permissive` in the fixtures)
whose system prompt leaked through a still-pickable entry. The fixture
`fixtures/mobile-api.v1/forge-models.json` pins all of this: exactly
two pickable models, one local and one cloud.

## Voice mode request fields

`APIClient.sendMessage(..., voiceMode:)` sends `voice_mode: true` in
the request body when voice mode is on. The backend additionally
accepts a `voiceHint` field; iOS **intentionally does not send
`voiceHint`** today (no client-side hint source) — it is a
supported-but-unused field, not a gap.

## Legacy chat-path classification (no ambiguity)

| Path | Classification | Action |
|---|---|---|
| `POST /v1/chat/aria` | **primary** (this contract) | — |
| `POST /api/chat` | **legacy, still used** by notification quick-reply, ShareExtension, App Intents, Watch — NOT the main iOS chat | keep; retiring it means porting those surfaces first |
| `GET /api/conversations` | **live** — used as a token-validation ping | keep |
| `GET/DELETE /api/conversations/:id` | **compiled-but-dark** (no callers) | retirement candidate |

The legacy `ChatEvent.start/status/photos` cases are retained only
for the `/api/chat` protocol; `/v1/chat/aria` never emits `start`.
