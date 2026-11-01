# Changelog — public export

## Public v1 (initial public snapshot)

Curated public export of the Factotum iOS app (private development
through version 4.1.1). Published as a fresh-history snapshot: no
private git history, operational changelogs, narrative development
docs, or live configuration are included.

For this export:

- Contract fixtures reviewed file by file; examples derived from real
  usage (the day-replay pair and the readiness summary) were replaced
  with generated equivalents that pass the same verification.
- Backend endpoints moved behind a configurable base URL with an
  example value (`AppConfig.backendBaseURL`).
- Bundle identifiers, the development team ID, and App Store Connect
  identifiers replaced with placeholders / environment variables.
- Backend contract docs rewritten as contract shapes with example
  service and table names.
- The app sources keep their original ARIA naming; see the README's
  naming note.
