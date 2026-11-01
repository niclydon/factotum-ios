# ARIA iOS Mobile-Write Contract

> **OB-52304** (aria-ios/nexus-data-contract). One standard for how the ARIA iOS
> app sends *client-originated writes* into Nexus: idempotency keying, offline
> replay, retry-safe error classification, and duplicate/moot handling. The
> executable core is `ARIA/Services/MobileWriteContract.swift`; this doc is the
> per-endpoint table it enforces.

## Why this exists

Before OB-52304 the retry/idempotency behavior was implemented ad hoc inside
`CardStore` and nowhere else, so each write endpoint behaved differently. Two
concrete defects motivated the standard:

1. A transient **5xx during offline replay** of a queued card decision was caught
   by a generic `catch` and **dropped as if the decision were moot** — the write
   silently vanished. It is now retried (bounded), because a 5xx is retry-safe on
   an idempotent endpoint.
2. There was **no shared classifier**: `APIError` folded every 4xx and 5xx into
   one `.serverError`, and raw `URLError` transport failures escaped unwrapped, so
   "offline" vs "retryable server" vs "validation" vs "auth-expired" could only be
   told apart in one place (`CardStore`, via `catch is URLError`).

## The classifier (single source of truth)

Every write failure is classified into one `WriteFailureCategory`
(`MobileWriteContract.swift`). `Error.writeFailureCategory` maps `APIError`,
raw `URLError`, and unknown errors uniformly:

| Category | Trigger | Queue behavior |
|---|---|---|
| `offline` | `URLError` (no connectivity / DNS / timeout) | keep queued, replay on reconnect; **no** attempt spent |
| `retryableServer` | HTTP 5xx, `invalidResponse` | keep queued, replay bounded by `maxReplayAttempts` (8) |
| `validation` | HTTP 4xx except 401 (stale / moot / malformed / 404) | **drop** — never loop |
| `unauthorized` | HTTP 401 | keep queued but **pause** replay until re-auth (not dropped) |

Rule the contract guarantees: **a server 5xx (or any non-2xx) is never recorded
as a successful write.** Success advances local "done" state (a `SyncHash`, a
`lastSyncDate`, or dropping a queue item) *only* on a 2xx — including an
idempotent duplicate that the server accepts as 2xx.

## Idempotency keys

- **Card decisions** carry a client-supplied key `"<cardId>:<action>"`
  (`MobileWriteContract.cardDecisionKey`) — kept byte-identical to the shipped
  convention so replays of decisions queued by an older build collapse onto the
  same server key (safe migration, not a new keyspace). The Matrix bridge's
  `resolveCard` is CAS-idempotent on it.
- **Device-sync writes** need no client key: the Nexus handlers are
  **content-upsert idempotent** server-side (a replayed re-sync is counted as an
  idempotent conflict, not a duplicate row). Replaying the same batch is safe.
- **Card replies** (free-text, LIFE) have no natural key; the bridge maps text to
  an action via `parseReply` and runs the same idempotent `resolveCard`.
- New keyed endpoints use `MobileWriteContract.key(route:entity:action:)`
  (`"<route>:<entity>[:<action>]"`).

## Per-endpoint contract (active/live writes)

| Endpoint | Idempotency | Retry strategy on failure | Duplicate / moot outcome |
|---|---|---|---|
| `POST /api/cards/:id/decide` | client key `cardId:action` | offline/5xx → **persistent queue** (`CardStore.pending`, replayed on next `load()`); 4xx → drop | body `outcome` ∈ `already_decided`/`not_open` = moot success, receipt applied |
| `POST /api/cards/:id/reply` | none (free text) | same persistent queue | body `outcome == no_action_parsed` = left open |
| `POST /api/health-data` | server content-upsert | fail → **no** local success; the per-type HealthKit anchor is not advanced, so the next `SyncCoordinator` sweep re-sends from the last durable anchor | idempotent conflicts counted as producer activity |
| `POST /api/device-activity` (+ bulk) | server content-upsert | `MotionService` sets `lastSyncDate` only on 2xx; failure retries next cycle | duplicate re-sync upserts, no dup row |
| `POST /api/device-music` | server content-upsert | next sweep re-sends on failure | idempotent upsert |
| `POST /api/device-location`, `/api/device-visits` | server content-upsert (stable keys) | Location's own visit/significant-change wake re-sends | idempotent upsert |
| `POST /api/device-events` | client UUID per event (`DeviceEvent.id`) | offline/5xx/401 → keep in the durable queue (`DeviceEventQueue`, replayed by the intent, sweep, foreground and silent push); 4xx on a batch → halve the batch; 4xx on one event → dead-letter it (kept locally, ≤200) | `duplicate[]` = success; `rejected[]` (incl. `id:null`) → dead-letter |
| `POST /api/health-files` | `hk:<HKObject uuid>` | fail → per-type anchor not advanced; next sweep re-sends | `duplicate[]` = success; `rejected[]` logged + telemetry, anchor still advances (a rejected object would loop forever) |
| `POST /api/music-recommendations/:id/confirm` | recommendation id | user action; failure surfaces, user can retry | server edits the original post (idempotent-safe) |
| `POST` / `DELETE /api/notifications/device-token` | device token (natural key) | re-registered unconditionally at every launch; delete on explicit sign-out only | upsert / delete-by-token (see OB-52234) |

**Backend-missing writes** (contacts / calendar / reminders / homekit / geofences /
proactive / inbox / feedback / settings — see
`nexus/docs/aria-ios-endpoint-contract-inventory.md`) currently 404. A 404 is a
`validation` failure → **not retried** and never marked successful, which is the
correct behavior until those routes are re-ported (nexus OB-52318 / OB-52329).

## Tests / verification

There is no XCTest target in this repo (see
`aria-ios-nexus-release-verification.md` §4). The contract is verified by:

- **`MobileWriteContract.runSelfCheck()`** — a `#if DEBUG` launch-time assertion
  (wired in `AppDelegate`) pinning the key convention and the four-way failure
  classification. Traps on regression.
- **Backend duplicate/replay tests already exist** for the two representative
  endpoints named in the OB:
  - *card decision* — Matrix bridge `src/__tests__/decideRoute.test.ts` +
    `framework.test.ts` ("resolveCard idempotency + outcomes"): a replayed decide
    with the same `idempotency_key` is a harmless no-op.
  - *device-sync* — nexus `packages/api/src/routes/__tests__/ios-healthkit.test.ts`:
    idempotent conflicts (duplicate re-syncs) are counted as producer activity,
    not duplicated rows or errors.
- **Build-Mac compile** across all targets is the app-side build gate.
