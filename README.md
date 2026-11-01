# Factotum for iOS

> Public export, generated from a private working repository. This is a
> curated, fresh-history snapshot of the current tree — the private
> repository's history, operational docs, and live configuration are not
> included. Endpoints, bundle identifiers, team identifiers, and example
> data in this export are example values; point them at your own backend
> and signing identity to build.

Factotum is a personal AI assistant client for iPhone, iPad, and Apple
Watch. It is the phone-side surface of a self-hosted personal backend:
chat with a long-lived assistant thread, device-data sync (HealthKit,
location, motion, music), a daily "one big thing" readiness summary, a
review queue for decisions the backend needs a human to make, a
day-replay view that rebuilds any past day from the data the backend
holds, and on-device photo intelligence ("Lens") that describes and
indexes the photo library locally.

## A note on naming — read this first

This app was originally built under the name **ARIA**, and it shows: the
Xcode project is `ARIA.xcodeproj`, the app target and most types are
ARIA-named, the URL scheme is `aria://`, and the backend contract routes
are shaped like `/v1/chat/aria`. The product was later renamed Factotum.
A source-level rename is a separate project (it has App Store and
provisioning fallout) and has deliberately **not** been done here — the
public repository is named `factotum-ios`, the sources keep their
original names, and this README is the honest map between the two.

## What is in the tree

| Area | Where |
|---|---|
| iOS/iPad app | `ARIA/` (SwiftUI, Swift 6, `@Observable`) |
| Watch app | `ARIAWatch/` |
| Widgets + Live Activities | `ARIAWidgets/` |
| Share extension | `ShareExtension/` |
| Contract fixtures | `fixtures/mobile-api.v1/` + `ARIA/Models/ContractFixtures.swift` |
| Fixture verification | `scripts/verify-contract-fixtures.sh` / `.swift` |
| Backend contract docs | `docs/backend-data-contract.md`, `docs/chat-model-contract.md` |
| HealthKit enrichment spec | `docs/healthkit-enrichment-spec.md` |

## The backend contract

The app talks to a personal backend over HTTPS with a bearer token
(GitHub OAuth bootstrap in the reference implementation). The base URL
is **configurable**: see `AppConfig.backendBaseURL` in
`ARIA/Services/AppConfig.swift` — set the `FactotumBackendBaseURL` Info
key (or edit the example default, `https://api.example.com`) to point at
your own server. The contract the app expects — routes, response DTOs,
auth posture, freshness and degraded behavior — is documented in
`docs/backend-data-contract.md`; the chat/model-picker specifics are in
`docs/chat-model-contract.md`. Synthetic example payloads for every
response shape live in `fixtures/mobile-api.v1/` and are verified by:

```bash
bash scripts/verify-contract-fixtures.sh
```

All fixture content is synthetic. Any example that in the private tree
was derived from real usage has been replaced with generated data that
satisfies the same decoders and shape checks.

## Building

You need a Mac with a current Xcode. Set your own development team and
bundle identifiers first (`YOUR_TEAM_ID` and `com.example.factotum*`
are placeholders throughout the project files), then:

```bash
xcodebuild -project ARIA.xcodeproj -scheme ARIA \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Release scripts under `scripts/` are included in generalized form:
signing and App Store Connect identifiers are read from the environment
(`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`), and the OTA publishing
script is configured entirely through environment variables.

## License

Apache License 2.0; see `LICENSE`.
