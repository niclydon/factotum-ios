#!/usr/bin/env bash
# Build ARIA (Debug) for an iOS simulator, launch it, and fail unless every
# #if DEBUG runSelfCheck() in AppDelegate passed. Must run ON a Mac:
#   bash scripts/run-debug-selfchecks.sh   (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="$(mktemp -d)"
LOG="$(mktemp)"
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
import re
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
rts = sorted((rt for rt in d if "iOS" in rt), key=ver, reverse=True)
print(next(dev["udid"] for rt in rts for dev in d[rt] if dev["name"].startswith("iPhone")))')"

xcrun simctl boot "$UDID" 2>/dev/null || true
# Ad-hoc sign (no team, no profile) so the simulator app carries the real
# .entitlements: HealthKit rejects clinical types without `health-records`, which
# would trip HealthKitService.runAuthorizationSelfCheck() in an unsigned build.
xcodebuild -project ARIA.xcodeproj -scheme ARIA -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER= DEVELOPMENT_TEAM= \
  build | tail -3
APP="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'ARIA.app' | head -1)"
xcrun simctl install "$UDID" "$APP"

xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.example.factotum >"$LOG" 2>&1 &
LAUNCH_PID=$!
for _ in $(seq 1 45); do
  grep -q '\[selfcheck\]' "$LOG" && break
  kill -0 "$LAUNCH_PID" 2>/dev/null || break
  sleep 1
done
kill "$LAUNCH_PID" 2>/dev/null || true
xcrun simctl terminate "$UDID" com.example.factotum 2>/dev/null || true

if grep -q '\[selfcheck\] all passed' "$LOG"; then
  echo "PASS: DEBUG self-checks"
  exit 0
fi
echo "FAIL: DEBUG self-checks did not pass"
cat "$LOG"
exit 1
