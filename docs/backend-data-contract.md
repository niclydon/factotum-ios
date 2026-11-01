# Backend-fed mobile data contract

**Status:** reference contract for the Factotum iOS client. This is the
public, generalized form of the contract: it describes the shapes the
app expects from *a* personal backend. Service names, table names, and
hosts in the author's deployment are replaced with descriptive example
names; routes, DTO shapes, auth posture, and degraded behavior are as
the app implements them.

This document maps every network call the app makes to its contract
surface: owning route family, backing data (described, not named),
auth, freshness expectation, and what the app does when the call fails
or the route is absent. It also records which app-referenced endpoints
have **no** server implementation in the reference deployment, so a
reader does not assume a dark endpoint is live.

> No secrets, tokens, raw private records, or transcripts appear here.
> Auth is described by mechanism only.

## 1. Transport, base URL, and auth mechanism

- **Central client:** `ARIA/Services/APIClient.swift` — an `actor`
  singleton. URLSession timeouts: request 180s, resource 300s (tuned
  for chat SSE cold starts when the backend swaps models).
- **Base URL:** configurable — `AppConfig.backendBaseURL`, defaulting
  to the example value `https://api.example.com`, overridable with the
  `FactotumBackendBaseURL` Info key. The chosen value is stored in the
  shared Keychain at launch/login (`AuthManager`, `WatchAPIClient`
  reads the same Keychain entry).
- **Auth header:** every request carries
  `Authorization: Bearer <token>` when a token is present. Missing
  token → header omitted → server 401.
- **Token mint (bootstrap, not via the central client):** GitHub OAuth
  through `ASWebAuthenticationSession` at
  `GET {base}/auth/github?redirect_uri=aria://auth/callback`; the
  minted token returns on the `aria://auth/callback?token=…` redirect.
  This is the only call with no bearer token (it produces one).
- **Server-side posture (reference deployment):** a request is
  authorized if its bearer equals a configured shared secret, **or** it
  is a mobile JWT whose `email` claim equals the configured allow-listed
  account. One route family (card photos, below) is unauthenticated by
  design and HMAC-signed instead.
- **401 handling (client):** the generic request path throws
  `APIError.unauthorized`; the SSE path yields an
  `.error("Session expired — please sign in again")` event. Sign-out
  happens **only** on a genuine 401 from a conversations liveness
  probe; transient/offline/5xx failures keep the session.

### Route families

| Family | Prefix | Notes |
|---|---|---|
| Mobile API | `/api` | All `/api/*` app routes below; bearer gate. |
| Card photo | `/api/card-photo` | Registered ahead of the router; unauthenticated, HMAC-signed URL. |
| Chat | `/v1/chat` | Behind the platform auth middleware. |
| Channels | `/v1/channels` | Same. |
| Model catalog | `/v1/forge` | Proxies the model router's catalog. |

## 2. Live route inventory

R = read, W = write. All require the bearer token unless noted.

### 2a. Chat & conversations

| iOS caller | Method · Path | R/W | Backing data | Response DTO | Degraded behavior |
|---|---|---|---|---|---|
| `ChatViewModel.sendMessage` | POST (SSE) `/v1/chat/aria` | W | appends to the assistant channel's message table; wakes the agent runtime | `AsyncStream<ChatEvent>` named-event SSE (`text.delta`, `error`, `end`) | 401 → "Session expired" event; non-200 → "Server error (code)"; **no retry**; history persists server-side |
| `ChatViewModel.loadAriaHistory` | GET `/v1/channels/aria-direct/history?limit=N` | R | channel messages | `ChannelHistoryResponse{messages:[ChannelMessageDTO], has_more}` | `?before=<id>` cursor; limit clamp 1–200; throws → caller |
| `ModelPicker` / `listForgeModels` | GET `/v1/forge/models` | R | model router catalog | `ForgeModelsResponse{data:[ForgeModel]}` (client filters pickable/available/text+vlm) | upstream fail → 502 (10s timeout) |
| `AuthManager` liveness | GET `/api/conversations` | R | conversations + last messages | `{conversations:[{id,title,created_at,updated_at,last_message}]}` | token liveness probe; only 401 → sign-out |
| `ChatViewModel.getMessages` | GET `/api/conversations/:id` | R | messages | `{messages:[{id,conversation_id,role,content,created_at}]}` | throws → banner |
| delete conversation | DELETE `/api/conversations/:id` | W | messages, conversations | `{success:true}` | throws |
| notification quick-reply; App Intents (direct `URLSession`) | POST (SSE) `/api/chat` | W | conversations/messages; default chat model | legacy SSE `start`/`chunk`/`done{messageId,model}`/`error` | **LEGACY** — superseded by `/v1/chat/aria` for main chat; still live for quick-reply + Siri intents; LLM down → SSE `error` |

### 2b. Device data sync (write-mostly ingestion)

| iOS caller | Method · Path | R/W | Backing data | Response DTO | Degraded behavior |
|---|---|---|---|---|---|
| `HealthKitService.sync` | POST `/api/health-data` | W | raw health samples table + a data-source registry | `{synced,inserted,conflicted,errored,total}` | per-type anchored query, resume from a persisted per-type anchor saved only after a page's POSTs succeed; first pull / anchor reset bounded to a 30-day window; pages POSTed in 1000-row chunks; all-rows-error → registry `status='error'` (silent-stall guard); idempotent on a 7-column identity index |
| `LocationService.sync` | POST `/api/device-location` | W | raw device-location table | `{saved:true}` | 400 if no `location`; background error silent; background success heals the stale banner |
| `LocationService.syncVisit` | POST `/api/device-visits` | W | same table, visit source marker | `{saved:1}` | 400 if no `visit` |
| `MotionService.sync` / backfill | POST `/api/device-activity` | W | motion-activity table + registry | single `{saved}` / bulk `{saved,total,valid}` | conflict-free upsert on `(timestamp,source)`; silent-stall guard; 7-day backfill |
| `MusicKitService.sync` | POST `/api/device-music` | W | music + playlist tables + registry | `{synced,playlists_synced}` | 500-track chunks, hash dedup, 24h full re-sync |
| `DeviceEventSync.flush` (App Intents) | POST `/api/device-events` | W | raw device-event table → cleaned event stream → timeline | `{accepted,duplicate,rejected[{id,error}]}` | batches ≤200 from the on-phone queue (≤5000 events / 7 days); idempotent on the client UUID; per-item outcome — a bad item never fails the batch; 4xx on a batch halves it, on one event dead-letters it |
| `HealthFilesSync.sync` | POST `/api/health-files` | W | clinical / ECG / route health tables + registry | `{accepted,duplicate,rejected}` | ids are `hk:<HealthKit object uuid>`; per-type anchor advances only after an ack covering every item; ECG/routes last 30 days |
| `MusicKitService.fetchMusicRecommendation` | GET `/api/music-recommendations/current` | R | recommendations table | rec DTO `{id,state{…},steer_direction,tracks[]…}` | **404 when no rec in last 2h** → app treats as nil |
| `MusicKitService.confirmMusicRecommendation` | POST `/api/music-recommendations/:id/confirm` | W | recommendations (update) | `{ok:true,id}` | write fail → log only |
| macOS log reporter | POST `/api/log-reporter/ingest` | W | snapshot table (JSONB) | `201 {ok:true,id}` | 400 if all fields null |

### 2c. Push notifications & operator cards

| iOS caller | Method · Path | R/W | Backing data | Response DTO | Degraded behavior |
|---|---|---|---|---|---|
| `PushNotificationService.registerDeviceToken` | POST `/api/notifications/device-token` | W | delivery-methods table (upsert on `(channel,label)`) | `{ok:true}` | `is_sandbox=true` in DEBUG; 400 empty token; error → banner |
| `PushNotificationService.unregisterDeviceToken` | DELETE `/api/notifications/device-token` | W | delivery-methods (delete by token) | `{ok:true}` | errors swallowed |
| `<img>` in card body | GET `/api/card-photo?key=…&exp=…&sig=…` | R | object-storage thumbnails | `image/jpeg` (`Cache-Control: private, max-age=86400`) | **Unauthenticated**; HMAC over `key:exp`; 403 bad sig, 410 expired, 404 missing, 502 fetch-fail |

### 2d. Command lane and mobile surfaces

| iOS caller | Method · Path | R/W | Response DTO | Degraded behavior |
|---|---|---|---|---|
| `AskView.commandAsk` | POST `/api/command/ask` | R (read-only lane) | grounded answer + read tool calls | 429 (cap 3 in-flight); 504 (120s); 400 empty/>2000 chars |
| — (not wired in app UI) | POST `/api/command/confirm` | W | action result | requires `user_approved=true` + `approval_text`; agent allowlist |
| `ReviewStore` | GET `/api/mobile/review-cards?status=open\|recent`, POST `/api/mobile/review-cards/:id/decide` | R/W | review card DTOs (see `fixtures/mobile-api.v1/review-cards-*.json`) | first decision anywhere wins (409 `already_decided`) |
| `TodayStore` | GET `/v1/health/sleep/{nightly,recovery}`, `/v1/health/activity/{daily,workouts}`, `/v1/location/visits`, `/v1/timeline/events` | R | per-card DTOs | read-only; each card fails independently |
| `BootstrapStore` | GET `/api/mobile/bootstrap` | R | capability + freshness-threshold DTO (fixtures: `mobile-bootstrap-*.json`) | config-only; unknown features default off |
| freshness surfaces | GET `/api/mobile/freshness` | R | per-source freshness DTO (fixture: `mobile-freshness-mixed.json`) | aggregate states fresh/stale/error/empty |
| Replay | GET `/api/mobile/replay/day`, POST `/api/mobile/replay/ask` | R | day-pack + cited narrative DTOs (fixtures: `mobile-replay-*.json`) | per-family empty states carry data notes |
| One Big Thing | GET `/api/mobile/one-big-thing` | R | readiness DTO (fixture: `mobile-one-big-thing.json`) | missing inputs are explicit `status:"missing"`, never zero-filled |

## 3. Data-source summary

| Domain | iOS surface | Write path | Freshness / staleness signal |
|---|---|---|---|
| Health | `HealthKitService` | POST `/api/health-data` | registry last-success / `error` on all-rows-error; per-type anchor resume (30-day window) |
| Location / Visits | `LocationService` | POST `/api/device-location`, `/api/device-visits` | `.saved` gate; registry consecutive failures |
| Motion | `MotionService` | POST `/api/device-activity` | silent-stall guard; conflict-free upsert |
| Music | `MusicKitService` | POST `/api/device-music` | 24h full re-sync; rec GET 404 = "no fresh rec (last 2h)" |
| Device events | `DeviceEventSync` + `IngestIntents` | POST `/api/device-events` | per-automation last event surfaced in Data Sources |
| Health files | `HealthFilesSync` | POST `/api/health-files` | per-type anchors |
| Review cards | `ReviewStore` | GET/POST `/api/mobile/review-cards…` | first decision wins (409) |
| Today | `TodayStore` | — (read) | each card fails independently |
| Chat | `ChatViewModel` | POST `/v1/chat/aria`, GET history | server-persisted history; SSE liveness |
| Push tokens | `PushNotificationService` | POST/DELETE `/api/notifications/device-token` | upsert on `(channel,label)`; sandbox flag in DEBUG |

## 4. Dark / absent endpoints — do NOT assume live

The mobile API surface is exactly the routes in §2. The following
`/api/*` families have **no handler** in the reference deployment
(they 404). They are kept here as a guard: **do not revive a path here
without a matching, deliberately designed server route.** No current
app target calls any of them; remaining mentions are doc comments,
contract-fixture labels, telemetry route templates, and a few unused
DTO types.

- **Settings:** `/api/settings`, `/api/settings/prompt`
- **Inbox (legacy):** `/api/inbox`, `/api/inbox/unread-count`,
  `/api/inbox/read-all`, `/api/inbox/:id/read`, `/api/inbox/:id/feedback`
  (the app inbox was removed; the fixture DTOs in
  `fixtures/mobile-api.v1/inbox-list*.json` still pin the app-side shape)
- **Proactive (legacy):** `/api/proactive/settings`, `/api/proactive/debug`,
  `/api/proactive/insights`, … (service removed; fixtures still pin the DTOs)
- **Reports:** `/api/reports`, `/api/reports/:id/read`,
  `/api/reports/subscriptions…`
- **Notifications (beyond device-token):** `/api/notifications/methods`,
  `/api/notifications/device-preferences`, `/api/notifications/timing-feedback`
- **Self-improvement:** `/api/self-improvement…`
- **Geofences:** `/api/geofences…` (the app only stops legacy OS regions at launch)
- **HomeKit:** `/api/device-homekit…`
- **Device sync (unported):** `/api/device-calendar`, `/api/device-contacts`,
  `/api/device-reminders…`
- **Media / social:** `/api/photos/search`, `/api/photos/memories`,
  `/api/journal`, `/api/social/dashboard`, …
- **Profile / knowledge graph:** `/api/owner-profile…`,
  `/api/imessage/history`, `/api/event-log`
- **Feedback:** `/api/messages/:messageId/feedback`
- **Skills:** `/api/skills` — the platform serves `/v1/skills`; the
  `/api` path 404s (namespace mismatch, not a missing feature)

### Legacy / superseded (still partially live)

- **`POST /api/chat`** — superseded by `/v1/chat/aria` for primary
  chat, but still live for notification quick-reply and Siri intents
  (old `type:"chunk"` SSE protocol). The legacy `start`/`status`/
  `photos` event types exist only for this path.

## 5. Files that make no network calls (for completeness)

`NotificationStore.swift` (local defaults), `WidgetDataService.swift`
(App Group container writes), `VoiceService.swift` (on-device speech;
voice chat routes through the API client), `SyncCoordinator.swift`
(orchestrates other services' syncs; skips without a token).
