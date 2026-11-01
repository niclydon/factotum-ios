# ARIA iOS Mobile-Error Telemetry (client)

> **OB-52305** (aria-ios/observability). Client half of the privacy-safe
> mobile-error telemetry path. The full contract (envelope, server validation,
> privacy boundary, retention, operator query) lives in the Nexus doc
> `nexus/docs/aria-ios-mobile-error-telemetry.md`; this covers the app behavior.

## What emits

`ARIA/Services/MobileErrorTelemetry.swift` (an `actor`, `.shared`) posts a tiny
metadata-only envelope to `POST /api/telemetry/mobile-error` whenever the app
sees a backend failure. It is wired into `APIClient`:

- The generic `request<T>` error paths — transport failure (`network`), invalid
  response (`network`), `401` (`auth`), `4xx` (`http_4xx`), `5xx` (`http_5xx`),
  and an undecodable `2xx` (`decode`, i.e. contract drift).
- The chat SSE path (`sendMessage`) — `401` (`auth`), non-200 (`http_4xx`/`http_5xx`),
  and stream transport failure (`network`).

## Guarantees

- **Best-effort / non-blocking:** `emitTelemetry` fire-and-forgets a `Task`; the
  telemetry actor uses its own `URLSession` and swallows every failure. A user
  flow is never delayed or failed by telemetry.
- **Cannot recursively flood:** telemetry never routes through `APIClient`, and
  `record()` early-returns for any `/api/telemetry/` path. It is rate-limited to
  20 emits/60s with a 10s dedupe by `route+status+kind`.
- **Metadata-only + id-safe:** only aggregate fields are assembled; the request
  path is reduced to a route **template** (`routeTemplate`) so any id-looking
  segment becomes `:id` before it leaves the device. The server re-validates and
  drops anything off its allowlist.

## Verification

There is no XCTest target (see `docs/aria-ios-nexus-release-verification.md` §4).
`MobileErrorTelemetry.runSelfCheck()` (a `#if DEBUG` launch assertion wired in
`AppDelegate`) pins the route-template redaction and domain derivation. The
server-side redaction is unit-tested in nexus `ios-mobile-telemetry.test.ts`.
