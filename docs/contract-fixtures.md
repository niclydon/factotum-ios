# App-Facing Contract Fixtures

> Synthetic fixtures for the backend JSON shapes the app renders
> directly. A missing optional field, a renamed key, or a proxy error
> body has repeatedly made the native app look empty/broken even when
> the data existed; these fixtures pin the contract so that drift
> breaks a check before a release ships.

**Contract version:** `mobile-api` **v1** (fixtures pin **1.3.0**).

## Where they live

| Location | Role |
|---|---|
| `fixtures/mobile-api.v1/*.json` | versioned synthetic payloads (named by route surface) + `manifest.json` |
| `ARIA/Models/ContractFixtures.swift` | the same catalog embedded for DEBUG launch; `verifyAll()` decodes through **real** Codable models |
| `scripts/verify-contract-fixtures.sh` (+ `.swift`) | **documented verification command** — fails on decode/shape breakage |

Chat SSE shapes are pinned separately by
`ARIA/Models/ChatEventContract.swift` and described in
`docs/chat-model-contract.md`.

## Verification command

From the repo root:

```bash
bash scripts/verify-contract-fixtures.sh
```

1. **JSON + shape gate** (any host with Python 3) — parses every
   fixture, checks the manifest catalog matches the files on disk,
   and asserts required keys / outcome values.
2. **Swift Codable decode** (a Mac with `swift` on PATH) — decodes
   every fixture into DTO mirrors of the production models and fails
   non-zero on removed required fields, type mismatches, or malformed
   enum-like values.

DEBUG app launches also call `ContractFixtures.runSelfCheck()` from
`AppDelegate` (real production models; this repo has no XCTest
target). The CLI command is the CI/smoke-friendly path; the DEBUG
self-check is the in-app safety net.

## Fixture → app surface map

| Fixture file | Surface | What it proves |
|---|---|---|
| `forge-models` | Model picker (`GET /v1/forge/models`) | `isPickable` desktop-parity filter |
| `channel-history` / `channel-history-empty` | Chat history | `sender_id` → role mapping |
| `health-sync` | `POST /api/health-data` | batch ack (`synced` + optional counters) |
| `location-sync` / `visit-sync` | `POST /api/device-location`, `/device-visits` | save acks |
| `activity-sync` / `activity-bulk-sync` | `POST /api/device-activity` | single + bulk acks |
| `music-sync` | `POST /api/device-music` | tracks + playlists_synced |
| `device-token-ok` | `POST/DELETE /api/notifications/device-token` | registration ack |
| `command-ask` | `POST /api/command/ask` | grounded answer + toolCalls camelCase shape |
| `inbox-list` / `inbox-list-empty` | `GET /api/inbox` (dark route; DTO still pinned) | list DTO + empty success |
| `notification-methods` / `device-preferences` | notification settings DTOs | push method + prefs decode |
| `mobile-bootstrap-ready` / `mobile-bootstrap-minimal` | `GET /api/mobile/bootstrap` | config-only capabilities; `review_cards` advertised vs not |
| `review-cards-open` | Review tab list (`GET /api/mobile/review-cards`) | two open cards: reply-capture action (note required) + a select |
| `review-cards-recent` | Review tab Recent segment | one decided card |
| `review-card-decide-ok` / `-conflict` / `-note-required` | Decide (`POST /:id/decide`) | 200 receipt / 409 decided elsewhere / 400 note prompt |
| `mobile-freshness-mixed` | `GET /api/mobile/freshness` | aggregate freshness classes (fresh/stale/error/empty) + summary/platform |
| `mobile-one-big-thing` | `GET /api/mobile/one-big-thing` | readiness DTO with explicit missing inputs |
| `mobile-replay-day` / `mobile-replay-ask` | `GET /api/mobile/replay/day`, `POST /api/mobile/replay/ask` | day pack across families + cited narrative |
| `mobile-photo-intelligence` / `-enrich`, `mobile-photo-terms` | photo intelligence ingest acks | ack counts |
| `proactive-settings` / `proactive-insights` / `-empty` | proactive DTOs (dark routes; DTOs still pinned) | settings + insights list |

## Privacy

All fixture content is synthetic. No private card/message bodies,
real person names, raw transcripts, real device tokens, real health
measurements, real places, or secrets appear in any fixture.
Token-shaped strings use the `synthetic-` prefix only; identifiers
use patterned values (`11111111-…`, `aaaaaaaa-…`) or the example
locale (Springfield / Exampleton).

## Change rules

1. Additive optional fields on a live response → fixtures may omit
   them; update the backend contract if the field is published.
2. Rename / remove / type-change of a field the app requires →
   update `fixtures/mobile-api.v1/`, `ContractFixtures.swift`, and
   the verify script in the same change.
3. New live mobile route with a client DTO → add a fixture file, a
   manifest entry, and a decoder case in the same change.
