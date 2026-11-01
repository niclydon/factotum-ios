# ARIA iOS Sync-Freshness Contract (app ↔ Nexus source registry)

> **OB-52233**. Unifies the two "is this source fresh?" truths: the app's local
> `SyncFreshness` (app-group snapshot) and Nexus's server-side
> `data_source_registry`. They diverged because the app used short keys while
> Nexus uses long ones, so a source could read connected in one and stale in the
> other. The canonical mapping now lives in one place —
> `ARIA/Models/DeviceSource.swift` — and every Settings row + trace resolves
> through it.

## Trace table (Settings row → service → route → registry row)

| Settings row | Service (`sourceKey`) | App freshness key | Sync API route | Nexus `data_source_registry.source_key` | Enabled flag |
|---|---|---|---|---|---|
| Health | `HealthKitService` (`health`) | `health` | `POST /api/health-data` | `healthkit` | `healthkit_enabled` |
| Motion & Activity | `MotionService` (`motion`) | `motion` | `POST /api/device-activity` | `device_motion_activity` | `motion_enabled` |
| Music | `MusicKitService` (`music`) | `music` | `POST /api/device-music` | `device_music` | `music_enabled` |
| (Location) | `LocationService` | `location` | `POST /api/device-location`, `/api/device-visits` | `device_location` | `location_enabled` |

The three sweep participants (Health/Motion/Music) report a `lastSyncDate` into
the `SyncCoordinator` snapshot and appear in the **Sync Freshness** UI. **Location
is intentionally not in the sweep** — it self-monitors via `CLVisit` +
significant-change OS wake, so it has no freshness-UI row but still advances its
own `device_location` registry row. `DeviceSource.freshnessSweepSources` is the
UI list; `DeviceSource.all` is the full mapping.

## Freshness thresholds & status meanings

**App-side (local, per source `lastSyncDate` — `SyncFreshnessView.statusColor`):**

| Age of last sync | Dot | Meaning |
|---|---|---|
| `< 6h` | green | fresh |
| `6h–24h` | amber | aging |
| `≥ 24h` | red | stale |
| never | grey | no sync recorded |

The "Keep ARIA synced" reminder fires only if the sweep has been silent for
**> 14h** (`SyncReminderScheduler`).

**Nexus-side (`data_source_registry.status`, set by the iOS route handlers):**

| Event | Registry write |
|---|---|
| Successful sync | `status='active'`, `last_sync_at=NOW()`, `consecutive_failures=0`, `last_sync_count=<n>` (errors cleared) |
| All records failed | `status='error'`, `last_sync_count=0`, `consecutive_failures += 1`, `last_error` set — the **silent-stall guard**: a POST that inserts zero rows must NOT leave the source looking active |
| Partial failure | success accounting + a `partialError` note (accepted count still recorded) |

**Why the two scales differ (documented, per acceptance):** the app colors by
*wall-clock age* of the last successful sweep (a device-side "have I phoned home
recently" signal), while Nexus classifies by *insert outcome* (`active`/`error`
from the last POST). They are complementary, not contradictory: a red app dot
means the device hasn't synced in ≥24h; a Nexus `error` means the last POST that
did arrive wrote zero rows. A coder diagnosing "disconnected" checks both — the
app dot for "is the device reaching the server", the registry row for "did the
server accept the write".

## Invariants

- **Offline/transient failures never clear a user's source enables.** Only an
  explicit sign-out (`.ariaDidLogout`) runs `disconnectAllServices()`; a 401 is
  the only thing that invalidates the session (the 2026-07-03 auth-cascade fix —
  see `CHANGES.md`). A DNS blip / 5xx / timeout at launch leaves every
  `*_enabled` flag intact so auto-SSO resumes syncing.
- **Success advances the registry; failure marks it.** A sync that throws never
  advances the app's `lastSyncDate` (set only after a 2xx) and never marks the
  Nexus row active (all-failed → `error`).

## Tests

- Backend: `packages/api/src/routes/__tests__/ios-healthkit.test.ts` covers a
  **successful** registry update (accepted + idempotent-conflict counting) and a
  **partial-failed** update (accepted volume preserved + error surfaced). The
  all-failed → `status='error'` silent-stall guard is implemented inline in the
  `/api/health-data` handler.
- App: `DeviceSource.runSelfCheck()` (`#if DEBUG`, wired in `AppDelegate`) pins
  the app-key ↔ Nexus-registry-key mapping so the two can't silently drift.

## Nexus-reported freshness aggregate (OB-52302)

`GET /api/mobile/freshness` returns **server-side** aggregate status for health,
location, motion, music, cards, chat, and push — plus platform bridge/queue
classes. The app stores this in `FreshnessStore` and renders it in
`SyncFreshnessView` **alongside** local `SyncFreshness` last-run times:

| Layer | Source of truth | Overwrite? |
|---|---|---|
| Local last-run | `SyncCoordinator` / `SyncFreshness` app-group snapshot | Never replaced by server |
| Nexus status | `FreshnessStore` / `GET /api/mobile/freshness` | Soft-refresh; cache on failure |

Status classes from Nexus: `fresh` / `stale` / `error` / `empty` / `unknown` /
`disabled`. Failure class is a token only (e.g. `past_expected_cadence`,
`registry_error`, `bridge_unreachable`) — never free-text errors or private
payloads. When overall is `degraded` or `error`, Sync Freshness shows copy that
empty screens may mean backend unhealthy rather than “no data”.

## Out of scope (follow-up owners named, not implicit)

The formerly compiled-but-dark sources (Contacts/Calendar/Reminders/HomeKit/Geofences)
POSTed to `backend-missing` routes and had no `data_source_registry` row. They
were retired rather than restored: Contacts/Calendar/Reminders/HomeKit on
2026-07-15 (**OB-52329**), Geofences on 2026-09-25 (the app now only clears
the stale `geofence_enabled` flag and any legacy OS regions). They are
deliberately absent from `DeviceSource.all` (which lists only sources with a
live registry row).
