#!/usr/bin/env bash
# OB-58883: make the canonical iOS build host (the build Mac) self-repair after an Xcode auto-update, so a
# TestFlight cut never fails opaquely at archive with "iOS 26.5 is not installed" / "Found no
# destinations for the scheme". Xcode updates the SDK underneath the host; the matching platform
# runtimes (iOS + watchOS, because ARIA embeds a Watch app) and first-launch are NOT auto-completed
# without authorization. the build Mac has passwordless `sudo -n`, so this repairs them in place.
#
# Idempotent: a no-op on an already-ready host. Reusable standalone (`bash scripts/xcode-preflight.sh`)
# and sourced by release.sh's preflight_xcode step. Off a Mac (no xcodebuild) it logs and returns 0 so
# the release path's other guards still run; it only ever does real work on the build host.
set -uo pipefail

# ARIA embeds a Watch app, so the scheme requires BOTH platforms installed to build.
XCODE_PREFLIGHT_PLATFORMS=("iOS" "watchOS")
XCODE_PREFLIGHT_MIN_FREE_GB="${XCODE_PREFLIGHT_MIN_FREE_GB:-12}"   # each platform sim is ~8.5 GB

_xp_log() { echo "[xcode-preflight] $*"; }

# free GB on the volume backing Xcode's downloads (~/Library/Developer)
_xp_free_gb() { df -g "$HOME/Library/Developer" 2>/dev/null | awk 'NR==2{print $4}'; }

# Is the platform's device destination eligible for the ARIA scheme? (installed + first-launch done)
_xp_platform_ready() {
  local plat="$1"
  xcodebuild -project ARIA.xcodeproj -scheme ARIA -showdestinations 2>/dev/null \
    | grep -E "platform:$plat" | grep -qv 'Ineligible'
}

xcode_preflight() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    _xp_log "no xcodebuild on PATH — not a Mac build host; skipping (release path's other guards still apply)"
    return 0
  fi
  # Version provenance into the log so every TestFlight build records the toolchain it was cut with.
  _xp_log "$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
  _xp_log "SDKs: $(xcodebuild -showsdks 2>/dev/null | grep -iE 'iphoneos|watchos' | tr '\n' ';')"
  _xp_log "runtimes: $(xcrun simctl list runtimes 2>/dev/null | grep -iE 'iOS|watchOS' | tr '\n' ';')"

  # 1. First-launch: Xcode updates leave this incomplete (exit 69). Complete it once.
  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    _xp_log "first-launch incomplete (post-update) — running sudo -n xcodebuild -runFirstLaunch"
    if ! sudo -n xcodebuild -runFirstLaunch; then
      _xp_log "FATAL: could not complete Xcode first-launch (sudo -n unavailable?). Run 'sudo xcodebuild -runFirstLaunch' on the host." >&2
      return 1
    fi
  fi

  # 2. Platform runtimes: iOS AND watchOS must be installed for the ARIA scheme to build.
  local plat freegb
  for plat in "${XCODE_PREFLIGHT_PLATFORMS[@]}"; do
    if _xp_platform_ready "$plat"; then
      _xp_log "$plat platform present and eligible"
      continue
    fi
    freegb="$(_xp_free_gb)"
    if [ -n "$freegb" ] && [ "$freegb" -lt "$XCODE_PREFLIGHT_MIN_FREE_GB" ]; then
      _xp_log "FATAL: $plat platform is missing but only ${freegb}GB free (< ${XCODE_PREFLIGHT_MIN_FREE_GB}GB needed to download it). Free space, then retry." >&2
      return 1
    fi
    _xp_log "$plat platform missing — running sudo -n xcodebuild -downloadPlatform $plat (~8.5 GB)"
    if ! sudo -n xcodebuild -downloadPlatform "$plat"; then
      _xp_log "FATAL: could not download the $plat platform (sudo -n unavailable, or the download failed)." >&2
      return 1
    fi
    if ! _xp_platform_ready "$plat"; then
      _xp_log "FATAL: $plat still not eligible after download — inspect 'xcodebuild -showdestinations -scheme ARIA'." >&2
      return 1
    fi
    _xp_log "$plat platform downloaded and eligible"
  done
  _xp_log "host ready: first-launch complete, iOS + watchOS platforms eligible"
  return 0
}

# Run directly when invoked as a script (not when sourced).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
  xcode_preflight
fi
