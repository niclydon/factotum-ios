#!/usr/bin/env bash
# OB-52300 — decode every synthetic mobile-api.v1 fixture into Swift DTOs.
#
# Usage (from aria-ios repo root):
#   bash scripts/verify-contract-fixtures.sh
#
# On macOS (Swift available): runs scripts/verify-contract-fixtures.swift
# which decodes every fixtures/mobile-api.v1/*.json file through Codable DTOs
# and fails non-zero on removed required fields, type mismatches, or bad enums.
#
# On Linux authoring hosts without Swift: validates JSON parse + required-key
# surface via Python (shape gate). Still requires the build Mac for the full Swift decode.
#
# Canonical iOS compile (when Swift sources change):
#   xcodebuild -project ARIA.xcodeproj -scheme ARIA -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/fixtures/mobile-api.v1"
cd "$ROOT"

if [[ ! -d "$FIX" ]]; then
  echo "FAIL: missing $FIX" >&2
  exit 1
fi

# ── Always: JSON parse + catalog completeness ───────────────
python3 - <<'PY'
import json, sys, pathlib
root = pathlib.Path("fixtures/mobile-api.v1")
manifest = json.loads((root / "manifest.json").read_text())
names = set(manifest["fixtures"])
files = {p.stem for p in root.glob("*.json") if p.name != "manifest.json"}
missing = names - files
extra = files - names
if missing:
    print(f"FAIL: manifest lists fixtures with no file: {sorted(missing)}", file=sys.stderr)
    sys.exit(1)
if extra:
    print(f"FAIL: fixture files not in manifest: {sorted(extra)}", file=sys.stderr)
    sys.exit(1)
for name in sorted(names):
    path = root / f"{name}.json"
    try:
        json.loads(path.read_text())
    except Exception as e:
        print(f"FAIL: {name}: invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
# Required-key shape gate (mirrors production non-optional fields).
checks = {
    "forge-models": lambda d: isinstance(d.get("data"), list) and len(d["data"]) >= 2,
    "channel-history": lambda d: isinstance(d.get("messages"), list) and len(d["messages"]) == 2,
    "channel-history-empty": lambda d: d.get("messages") == [],
    "health-sync": lambda d: d.get("synced") == 3,
    "location-sync": lambda d: d.get("saved") is True,
    "visit-sync": lambda d: d.get("saved") == 2,
    "activity-sync": lambda d: d.get("saved") is True,
    "activity-bulk-sync": lambda d: d.get("saved") == 4 and d.get("total") == 4,
    "music-sync": lambda d: d.get("synced") == 5,
    "device-token-ok": lambda d: d.get("ok") is True,
    "command-ask": lambda d: d.get("answer") and "toolCalls" in d and "readToolCount" in d,
    "inbox-list": lambda d: len(d.get("items", [])) == 1 and d.get("unreadCount") == 1,
    "inbox-list-empty": lambda d: d.get("items") == [] and d.get("total") == 0,
    "notification-methods": lambda d: len(d.get("methods", [])) == 1,
    "device-preferences": lambda d: len(d.get("devices", [])) == 1,
    "proactive-settings": lambda d: d.get("settings", {}).get("risk_level") == "balanced",
    "proactive-insights": lambda d: len(d.get("insights", [])) == 1,
    "proactive-insights-empty": lambda d: d.get("insights") == [],
    "mobile-freshness-mixed": lambda d: (
        d.get("contract_version") == "1.0.0"
        and isinstance(d.get("sources"), list) and len(d["sources"]) == 7
        and d.get("summary", {}).get("overall") == "error"
        and "worker_queue" in d.get("platform", {})
    ),
    "review-cards-open": lambda d: d.get("contract_version") == "1.3.0" and len(d.get("cards", [])) == 2
        and all(all(k in c for k in ("id", "kind", "domain", "title", "body", "status", "actions", "selects", "reply_capture_actions")) for c in d["cards"])
        and bool(d["cards"][0]["reply_capture_actions"].get("link_person"))
        # OB-58965 (1.2.0): last_outcome is optional; the first card carries a reopened-after-skip reason
        and bool((d["cards"][0].get("last_outcome") or {}).get("reason")) and d["cards"][1].get("last_outcome") is None,
    "review-cards-recent": lambda d: len(d.get("cards", [])) == 1 and d["cards"][0]["status"] == "decided",
    "review-card-decide-ok": lambda d: d.get("card", {}).get("status") == "decided",
    "review-card-decide-conflict": lambda d: d.get("error") == "already_decided" and "card" in d,
    "review-card-decide-note-required": lambda d: d.get("error") == "note_required" and bool(d.get("prompt")),
    "mobile-bootstrap-ready": lambda d: d.get("contract_version") == "1.3.0" and d["supported_features"].get("review_cards") is True and "card_surface" not in d,
    "mobile-bootstrap-minimal": lambda d: d["supported_features"].get("review_cards") is False,
    "device-events-ack": lambda d: all(isinstance(d.get(k), list) for k in ("accepted", "duplicate", "rejected")) and d["rejected"][0]["id"] is None,
    "health-files-ack": lambda d: all(isinstance(d.get(k), list) for k in ("accepted", "duplicate", "rejected")) and d["accepted"][0].startswith("hk:"),
}
for name, fn in checks.items():
    body = json.loads((root / f"{name}.json").read_text())
    if not fn(body):
        print(f"FAIL: required-key/shape check failed for {name}", file=sys.stderr)
        sys.exit(1)
print(f"ok  json+shape gate: {len(names)} fixtures (contract {manifest.get('contract_version')})")
PY

# ── Swift Codable decode when available ─────────────────────
if command -v swift >/dev/null 2>&1; then
  echo "running Swift Codable decoder…"
  swift "$ROOT/scripts/verify-contract-fixtures.swift"
else
  echo "SKIP full Swift decode (no swift on PATH)."
  echo "  On a Mac: bash scripts/verify-contract-fixtures.sh"
  echo "  Or:       swift scripts/verify-contract-fixtures.swift"
  # Still exit 0 on the shape gate so Linux authoring can preflight;
  # the OB close evidence must include an the build Mac Swift run when sources change.
fi
