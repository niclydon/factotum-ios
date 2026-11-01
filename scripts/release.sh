#!/usr/bin/env bash
# Release pipeline for ARIA iOS — meant to run on a Mac with Xcode + an Apple
# Developer account configured. Modeled on a sibling project's
# scripts/release.sh (the working canonical pattern for this family).
#
# Editing happens anywhere. Building and uploading must happen on a
# Mac because Apple's iOS toolchain is macOS-only. The build Mac is
# the canonical build host: it has Xcode and the App Store Connect
# API key.
#
# Differences from example-ios's version:
#   - aria-ios uses a checked-in Xcode project (ARIA.xcodeproj), not a
#     project.yml + xcodegen. So no `xcodegen generate` step.
#   - Versions live ONLY in ARIA.xcodeproj/project.pbxproj: all 4
#     iOS-family Info.plists (ARIA, ARIAWatch, ARIAWidgets,
#     ShareExtension) interpolate $(MARKETING_VERSION) and
#     $(CURRENT_PROJECT_VERSION) from the pbxproj build settings.
#     The bump (step 1 below) rewrites CURRENT_PROJECT_VERSION in
#     the pbxproj and asserts every target agrees before and after.
#     (Fixed 2026-10-26: the previous plist-walking bump and guard
#     dated from a pre-interpolation project shape and could not
#     run against the current one.)
#   - Same Apple Developer account → same ASC_KEY_ID / ASC_ISSUER_ID /
#     TEAM_ID as a sibling project. The .p8 key at
#     ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 is shared.
#
# Prereqs (one-time per Mac):
#   brew install xcodegen          # (used by a sibling project but not strictly needed for ARIA)
#   ~/.appstoreconnect/private_keys/AuthKey_YOUR_ASC_KEY_ID.p8  (from secrets vault)
#   Apple Developer team membership active and accepted PLA
#
# Usage:
#   ./scripts/release.sh                 # auto-bumps CURRENT_PROJECT_VERSION +1
#   ./scripts/release.sh --no-bump       # uses whatever's in project.pbxproj
#   ./scripts/release.sh --skip-upload   # archive + export only
#   ./scripts/release.sh --skip-xcode-preflight  # skip the the build Mac Xcode host-readiness check (OB-58883)

set -euo pipefail
cd "$(dirname "$0")/.."

# Single-instance lock. Two concurrent release.sh runs uploading the same
# IPA caused altool's S3 multipart-upload sessions to collide on Apple's
# CDN — connections dropped mid-part with NSURLErrorDomain Code=-1005,
# altool entered a checksum-retry loop that never converged, and both
# uploads stalled for 10+ minutes (CHANGES.md 2026-04-26 incident). mkdir
# is the portable atomic primitive — flock isn't shipped with macOS.
RELEASE_LOCK_DIR=/tmp/aria-ios-release.lock
if ! mkdir "$RELEASE_LOCK_DIR" 2>/dev/null; then
  existing_pid=$(cat "$RELEASE_LOCK_DIR/pid" 2>/dev/null || echo "?")
  if [ "$existing_pid" != "?" ] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "ERROR: another release.sh is already running (PID $existing_pid)." >&2
    echo "       Wait for it to finish, or 'kill $existing_pid' if it's hung in altool." >&2
    exit 1
  fi
  echo "WARN: stale lock at $RELEASE_LOCK_DIR (owner PID $existing_pid is gone) — clearing"
  rm -rf "$RELEASE_LOCK_DIR"
  mkdir "$RELEASE_LOCK_DIR"
fi
echo "$$" > "$RELEASE_LOCK_DIR/pid"

# Build a throwaway keychain from the Apple Distribution cert stored in the
# secrets vault, then use it for codesign. This replaces the old
# "rely on the login keychain being unlocked" approach which broke any
# time the build Mac slept, rebooted, or the script was invoked from a non-TTY
# context (Claude's Bash tool, cron, ssh without -t — see git history of
# this file on 2026-04-26 for the full bug story).
#
# Pattern is the same one whittled's GitHub Actions testflight.yml uses.
# The cert lives in AWS Secrets Manager at example/apple-distribution-cert
# (managed via secrets-vault `sv push`). Same physical cert as the one in
# the build Mac's login keychain — just made portable so any non-TTY runner can
# import it on demand.
SIGN_KEYCHAIN="$(mktemp -dt sign-keychain).keychain-db"
SIGN_P12="$(mktemp -t sign-p12-XXXX).p12"
SIGN_KEYCHAIN_PASS="$(/usr/bin/openssl rand -hex 16)"
cleanup() {
  rm -rf "$RELEASE_LOCK_DIR"
  security delete-keychain "$SIGN_KEYCHAIN" 2>/dev/null || true
  rm -f "$SIGN_P12"
  # Restore the user keychain search list to the default (login keychain only).
  security list-keychains -d user -s login.keychain-db 2>/dev/null || true
}
trap cleanup EXIT

echo "==> fetching Apple Distribution cert from vault"
SIGN_AWS_PROFILE="${AWS_PROFILE:-secrets}"
SIGN_AWS_REGION="${AWS_REGION:-us-east-1}"
SIGN_VAULT_JSON=$(aws secretsmanager get-secret-value \
  --secret-id example/apple-distribution-cert \
  --profile "$SIGN_AWS_PROFILE" \
  --region "$SIGN_AWS_REGION" \
  --query SecretString --output text)
SIGN_P12_PASS=$(printf '%s' "$SIGN_VAULT_JSON" \
  | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["password"])')
printf '%s' "$SIGN_VAULT_JSON" \
  | python3 -c 'import base64,json,sys; sys.stdout.buffer.write(base64.b64decode(json.loads(sys.stdin.read())["p12_base64"]))' \
  > "$SIGN_P12"

echo "==> creating throwaway signing keychain"
security create-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN"
security set-keychain-settings -lut 21600 "$SIGN_KEYCHAIN"
security unlock-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN"
security import "$SIGN_P12" -P "$SIGN_P12_PASS" -A -t cert -f pkcs12 -k "$SIGN_KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN" >/dev/null
security list-keychains -d user -s "$SIGN_KEYCHAIN" login.keychain-db
unset SIGN_VAULT_JSON SIGN_P12_PASS SIGN_KEYCHAIN_PASS

# Signing constants come from the environment — set them for your
# own Apple Developer account. Pulled once from the dev portal;
# they won't change.
TEAM_ID="${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
ASC_KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

DO_BUMP=1
DO_UPLOAD=1
ALLOW_UNPUSHED=0
DO_XCODE_PREFLIGHT=1
RELEASE_BRANCH=main
while [ $# -gt 0 ]; do
  case "$1" in
    --no-bump) DO_BUMP=0 ;;
    --skip-upload) DO_UPLOAD=0 ;;
    --allow-unpushed) ALLOW_UNPUSHED=1 ;;   # OB-58882: emergency bypass of the pushed-to-origin guard (logged loudly)
    --branch) shift; RELEASE_BRANCH="${1:?--branch needs a name}" ;;
    --skip-xcode-preflight) DO_XCODE_PREFLIGHT=0 ;;   # OB-58883: bypass the the build Mac Xcode host-readiness check
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
  shift
done

# OB-58882: preflight the git state BEFORE any bump/build so a TestFlight cut can never ship code
# that lives on no branch on origin (the build-122 incident: OB-54163 shipped from an unpushed local
# branch and was closed as live while its code sat on one Mac). Three checks + a loud emergency bypass.
#   1. Working tree clean, EXCLUDING the 4 Info.plists this script bumps (a prior dry-run may have left
#      them dirty; the real fix — auto-commit-on-upload — is below).
#   2. HEAD is on the release branch (default main; override with --branch).
#   3. HEAD is an ancestor of origin/<branch> (i.e. every commit being built is already on origin).
preflight_git() {
  local dirty
  dirty=$(git status --porcelain --untracked-files=no     | grep -vE ' (ARIA|ARIAWatch|ARIAWidgets|ShareExtension)/Info\.plist$' || true)
  if [ -n "$dirty" ]; then
    echo "ERROR (OB-58882): working tree has uncommitted changes outside the Info.plists — refusing to release." >&2
    echo "$dirty" >&2
    echo "       Commit or stash them so origin matches what testers install." >&2
    exit 1
  fi
  local head_branch
  head_branch=$(git rev-parse --abbrev-ref HEAD)
  if [ "$head_branch" != "$RELEASE_BRANCH" ]; then
    echo "ERROR (OB-58882): HEAD is on '$head_branch', not the release branch '$RELEASE_BRANCH'." >&2
    echo "       Check out $RELEASE_BRANCH, or pass --branch $head_branch if that is intentional." >&2
    exit 1
  fi
  git fetch -q origin "$RELEASE_BRANCH" 2>/dev/null || true
  if git merge-base --is-ancestor HEAD "origin/$RELEASE_BRANCH" 2>/dev/null; then
    echo "==> preflight: HEAD is on origin/$RELEASE_BRANCH (clean, pushed)"
  elif [ "$ALLOW_UNPUSHED" -eq 1 ]; then
    echo "WARNING (OB-58882): HEAD is NOT on origin/$RELEASE_BRANCH, but --allow-unpushed was passed." >&2
    echo "         Shipping unpushed code: the build testers install will exist on no branch on origin." >&2
  else
    echo "ERROR (OB-58882): HEAD ($(git rev-parse --short HEAD)) is not on origin/$RELEASE_BRANCH — unpushed commits would ship." >&2
    echo "       Push $RELEASE_BRANCH first, or pass --allow-unpushed for an audited emergency cut." >&2
    exit 1
  fi
}
preflight_git

# OB-58883: the build Mac Xcode host-readiness preflight. Xcode auto-updates on the build host bump the
# SDK underneath us but leave first-launch incomplete and the iOS/watchOS platform runtimes
# uninstalled, so an archive fails opaquely ('iOS N is not installed' / 'no destinations for the
# scheme'). This self-repairs those (passwordless sudo -n on the build Mac) before we archive. Reusable and
# a no-op off a Mac. --skip-xcode-preflight bypasses it for an audited emergency cut.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$DO_XCODE_PREFLIGHT" -eq 1 ]; then
  # shellcheck source=scripts/xcode-preflight.sh
  . "$SCRIPT_DIR/xcode-preflight.sh"
  if ! xcode_preflight; then
    echo "ERROR (OB-58883): Xcode host preflight failed; aborting before archive. See [xcode-preflight] lines above." >&2
    exit 1
  fi
else
  echo "==> skipping Xcode host preflight (--skip-xcode-preflight)"
fi

# 1. Bump CURRENT_PROJECT_VERSION in project.pbxproj in lockstep.
#    All 4 targets' Info.plists interpolate $(CURRENT_PROJECT_VERSION)
#    (and $(MARKETING_VERSION)) from the pbxproj, the sole version
#    source of truth. App Store Connect requires every embedded
#    extension to match the host app's build number, so every
#    CURRENT_PROJECT_VERSION entry must move together; the bump
#    asserts the targets agree before and after.
#
#    The tvOS target ARIATV (never part of this release path — the archive/
#    export/upload steps below build the iOS `ARIA` scheme only) was retired
#    outright on 2026-09-26: every one of its dashboard data feeds called an
#    endpoint with no Nexus handler, only its chat worked, and OB-52332's
#    "don't treat it as dead code" note had been an open-ended deferral, not
#    an active maintenance commitment. See CHANGES.md for the removal.
PBXPROJ=ARIA.xcodeproj/project.pbxproj
read_pbx_value() { grep -o "$1 = [^;]*" "$PBXPROJ" | awk '{print $3}' | sort -u; }
if [ "$DO_BUMP" -eq 1 ]; then
  current=$(read_pbx_value CURRENT_PROJECT_VERSION)
  if [ "$(printf '%s\n' "$current" | wc -l | tr -d ' ')" != "1" ]; then
    echo "ERROR: CURRENT_PROJECT_VERSION values disagree across targets in $PBXPROJ: $current" >&2
    exit 1
  fi
  count_before=$(grep -c "CURRENT_PROJECT_VERSION = $current;" "$PBXPROJ")
  next=$((current + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION = $current;/CURRENT_PROJECT_VERSION = $next;/g" "$PBXPROJ"
  after=$(read_pbx_value CURRENT_PROJECT_VERSION)
  count_after=$(grep -c "CURRENT_PROJECT_VERSION = $next;" "$PBXPROJ")
  if [ "$after" != "$next" ] || [ "$count_after" != "$count_before" ]; then
    echo "ERROR: bump verification failed in $PBXPROJ (value=$after count=$count_after, expected $next x$count_before)" >&2
    exit 1
  fi
  echo "==> bumped CURRENT_PROJECT_VERSION: $current -> $next ($PBXPROJ, $count_after entries)"
fi

# 1.5 Verify version-string consistency across all 4 targets. App Store
#     Connect buckets builds by CFBundleShortVersionString (the human
#     "3.0.0"-style version); CFBundleVersion (the build number)
#     only has to be unique inside that bucket. If the 4 plists drift,
#     the upload will land under whichever version the main app's
#     Info.plist names — silently invisible to testers on a different
#     version stream. This guard catches the drift before xcodebuild
#     does. (See CHANGES.md 2026-04-26 for the incident this prevents.)
SVS=$(read_pbx_value MARKETING_VERSION)
BV=$(read_pbx_value CURRENT_PROJECT_VERSION)
if [ "$(printf '%s\n' "$SVS" | wc -l | tr -d ' ')" != "1" ] || [ "$(printf '%s\n' "$BV" | wc -l | tr -d ' ')" != "1" ]; then
  echo "ERROR: version drift across targets in $PBXPROJ — MARKETING_VERSION values: $SVS / CURRENT_PROJECT_VERSION values: $BV" >&2
  exit 1
fi
echo "==> uploading as CFBundleShortVersionString=$SVS, CFBundleVersion=$BV"

# ASC API key path — used by xcodebuild for -allowProvisioningUpdates so the
# build doesn't need an Apple ID account configured in Xcode. Same key altool
# uses for the upload step.
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "ERROR: App Store Connect API key not found at $ASC_KEY_PATH"
  echo "       Copy it from the secrets vault before running release.sh."
  exit 1
fi

# 2. Archive Release build for generic iOS device.
# Tee xcodebuild's full output to a logfile so failures don't disappear
# behind the grep summary. PIPESTATUS[0] recovers xcodebuild's real exit
# code (grep's exit doesn't tell us anything we trust).
echo "==> archive"
rm -rf build/
mkdir -p build/
ARCHIVE_LOG=build/archive.log
set +e
# Per-target signing is wired into ARIA.xcodeproj/project.pbxproj (Release
# configs of ARIA, ARIAShare, ARIAWidgets, ARIAWatch each carry their own
# CODE_SIGN_IDENTITY=Apple Distribution + CODE_SIGN_STYLE=Manual +
# PROVISIONING_PROFILE_SPECIFIER pointing at the Store profile that
# matches its bundle ID). We do NOT pass those as cmdline overrides
# because xcodebuild applies cmdline settings to every target, and the
# main app's "ARIA iOS Distribution" profile is bound to com.example.factotum
# — wiring it globally breaks the 3 embedded targets which each need
# their own profile. OTHER_CODE_SIGN_FLAGS stays on cmdline because the
# throwaway keychain path is only known at runtime.
xcodebuild \
  -project ARIA.xcodeproj \
  -scheme ARIA \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/ARIA.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--keychain $SIGN_KEYCHAIN" \
  archive 2>&1 | tee "$ARCHIVE_LOG" | grep -E "ARCHIVE|error:" | tail -5
ARCHIVE_RC=${PIPESTATUS[0]}
set -e
if [ "$ARCHIVE_RC" -ne 0 ]; then
  echo "ERROR: archive failed (xcodebuild exit $ARCHIVE_RC). Last 60 log lines:" >&2
  tail -60 "$ARCHIVE_LOG" >&2
  echo "Full log: $(pwd)/$ARCHIVE_LOG" >&2
  exit "$ARCHIVE_RC"
fi
echo "==> archive succeeded"

# 3. Export to .ipa via the existing ExportOptions.plist.
echo "==> export ipa"
EXPORT_LOG=build/export.log
set +e
xcodebuild \
  -exportArchive \
  -archivePath build/ARIA.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/ \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" 2>&1 | tee "$EXPORT_LOG" | grep -E "EXPORT|error:" | tail -5
EXPORT_RC=${PIPESTATUS[0]}
set -e
if [ "$EXPORT_RC" -ne 0 ]; then
  echo "ERROR: export failed (xcodebuild exit $EXPORT_RC). Last 60 log lines:" >&2
  tail -60 "$EXPORT_LOG" >&2
  echo "Full log: $(pwd)/$EXPORT_LOG" >&2
  exit "$EXPORT_RC"
fi

# Find the produced .ipa (name varies with scheme/target naming)
IPA_PATH=$(ls build/*.ipa 2>/dev/null | head -1)
if [ -z "$IPA_PATH" ]; then
  echo "ERROR: no .ipa produced in build/"
  exit 1
fi
echo "==> exported $IPA_PATH"

# OB-58882: the committed CFBundleVersion must equal what the IPA actually carries. The checked-in
# ExportOptions.plist had manageAppVersionAndBuildNumber=true for a window in 2026, so
# -exportArchive silently renumbered every IPA to "latest ASC build + 1" — repo N shipped as N+10
# (repo "123" landed as 133), invisible to testers on the repo's version. Assert equality here and
# refuse to upload a build whose number does not match the source of truth.
# Select the HOST app's Info.plist by exact entry name: unzip's own wildcards match across '/',
# so 'Payload/*.app/Info.plist' also pulled in the embedded Watch app's plist and plutil rejected
# the concatenation. The `|| …=""` keeps a read failure on the WARNING path below instead of
# letting set -euo pipefail kill the script silently mid-assignment.
IPA_PLIST=$(unzip -Z1 "$IPA_PATH" 2>/dev/null | grep -E '^Payload/[^/]+\.app/Info\.plist$') || IPA_PLIST=""
IPA_PLIST=${IPA_PLIST%%$'\n'*}
IPA_BV=""
if [ -n "$IPA_PLIST" ]; then
  IPA_BV=$(unzip -p "$IPA_PATH" "$IPA_PLIST" 2>/dev/null \
    | plutil -extract CFBundleVersion raw -o - - 2>/dev/null) || IPA_BV=""
fi
if [ -z "$IPA_BV" ]; then
  echo "WARNING (OB-58882): could not read CFBundleVersion from $IPA_PATH to verify it matches the plists ($BV)." >&2
elif [ "$IPA_BV" != "$BV" ]; then
  echo "ERROR (OB-58882): the exported IPA carries CFBundleVersion=$IPA_BV but the Info.plists say $BV." >&2
  echo "       -exportArchive renumbered the build (check ExportOptions.plist manageAppVersionAndBuildNumber=false)." >&2
  echo "       Refusing to upload a build that ships under a different number than the repo records." >&2
  exit 1
else
  echo "==> IPA CFBundleVersion=$IPA_BV matches the plists"
fi

# 4. Upload to App Store Connect (TestFlight processing). altool is the same
#    pathway a sibling project uses; more reliable than xcodebuild's own upload step.
if [ "$DO_UPLOAD" -eq 1 ]; then
  echo "==> upload via altool"
  UPLOAD_LOG="build/upload.log"
  # Tee full altool output to a log file — previously this was `| tail -5`
  # with no persistence, so silent failures (build 116 incident, 2026-05-17)
  # left no trail. Now build/upload.log captures everything for postmortem,
  # and the exit status of altool propagates via PIPESTATUS so a failed
  # upload aborts the script instead of silently "succeeding".
  set -o pipefail
  xcrun altool --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$UPLOAD_LOG" | tail -10
  upload_status=${PIPESTATUS[0]}
  set +o pipefail

  if [ "$upload_status" -ne 0 ]; then
    echo
    echo "ERROR: altool upload failed (exit $upload_status). Full log: $UPLOAD_LOG"
    exit "$upload_status"
  fi

  # OB-58882: the uploaded build is now the one testers will install — commit+push the version bump
  # so origin matches it (the build-122 incident shipped a bump that was never committed/pushed).
  if [ "$DO_BUMP" -eq 1 ]; then
    if ! git diff --quiet -- "${INFO_PLISTS[@]}"; then
      git add "${INFO_PLISTS[@]}"
      git commit -q -m "chore(ios): bump CFBundleVersion to $BV (TestFlight)"
      if git push -q origin "HEAD:$RELEASE_BRANCH"; then
        echo "==> committed + pushed the CFBundleVersion $BV bump to origin/$RELEASE_BRANCH"
      else
        echo "WARNING (OB-58882): the $BV build uploaded but pushing the bump to origin/$RELEASE_BRANCH FAILED — push it manually so origin matches TestFlight." >&2
      fi
    fi
  fi

  echo
  echo "Upload submitted. Apple processing typically ~5-15 min."
  echo "Full log: $UPLOAD_LOG"
  echo "Check App Store Connect → TestFlight → Internal Testing for the build."
else
  echo "==> --skip-upload set; .ipa at $IPA_PATH"
  # An `if`, not `[ … ] && echo`: with set -e the failing test was the script's
  # last command under --no-bump, so a successful dry run exited 1.
  if [ "$DO_BUMP" -eq 1 ]; then
    echo "    (dry run: the CFBundleVersion $BV bump is left uncommitted — it is committed+pushed only on a real upload, OB-58882)"
  fi
fi
