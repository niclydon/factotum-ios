#!/usr/bin/env bash
# Publish an Ad Hoc IPA to the Factotum OTA page on the OTA server.
#
# Usage:
#   scripts/publish-ota.sh [--dry-run] <ipa> <version> <build> <release-notes.json>
#
# What it does, in order:
#   1. MD5s the IPA locally.
#   2. Reads the currently-published build from the docroot's
#      release-notes.json (for the backup directory name).
#   3. Backs up the current docroot IPA + manifest.plist +
#      release-notes.json to ~/ota-backup-<current-build>/ on ota-server.
#   4. Installs the new IPA and release-notes.json, rewrites the
#      manifest's bundle-version, fixes ownership/mode on the notes.
#   5. Verifies the docroot IPA's MD5 matches the local MD5 and that
#      the public release-notes URL serves the new version.
#
# Runs from any checkout of this repo. Reaches the OTA server with
# ssh/scp using the caller's own ssh setup; override with OTA_SSH /
# OTA_SCP if your host needs flags.
set -euo pipefail

DOCROOT=${OTA_DOCROOT:-/var/www/factotum-ios/your-build-token}
URL_BASE=${OTA_URL_BASE:-https://factotum-ios.example.com/your-build-token}
OTA_SSH=${OTA_SSH:-ssh ota-server}
OTA_SCP=${OTA_SCP:-scp}
OTA_USER=${OTA_USER:-deploy}

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; shift; fi
if [ $# -ne 4 ]; then
  echo "usage: $0 [--dry-run] <ipa> <version> <build> <release-notes.json>" >&2
  exit 2
fi
IPA=$1; VERSION=$2; BUILD=$3; NOTES=$4
[ -f "$IPA" ] || { echo "ERROR: IPA not found: $IPA" >&2; exit 1; }
[ -f "$NOTES" ] || { echo "ERROR: release notes not found: $NOTES" >&2; exit 1; }

if command -v md5sum >/dev/null 2>&1; then LOCAL_MD5=$(md5sum "$IPA" | awk '{print $1}');
else LOCAL_MD5=$(md5 -q "$IPA"); fi
echo "==> local IPA MD5: $LOCAL_MD5"

CUR_BUILD=$($OTA_SSH "python3 -c \"import json; print(json.load(open('$DOCROOT/release-notes.json'))['build'])\" 2>/dev/null" || echo prev)
echo "==> currently published build: $CUR_BUILD (backup: ~/ota-backup-$CUR_BUILD/)"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "==> DRY RUN: would back up build $CUR_BUILD, install $VERSION/$BUILD, set manifest bundle-version $VERSION, verify MD5 + public notes"
  exit 0
fi

$OTA_SCP "$IPA" ota-server:factotum-publish-ARIA.ipa
$OTA_SCP "$NOTES" ota-server:factotum-publish-release-notes.json

$OTA_SSH "
set -e
mkdir -p ~/ota-backup-$CUR_BUILD
sudo cp $DOCROOT/ARIA.ipa $DOCROOT/manifest.plist $DOCROOT/release-notes.json ~/ota-backup-$CUR_BUILD/
sudo cp ~/factotum-publish-ARIA.ipa $DOCROOT/ARIA.ipa
sudo cp ~/factotum-publish-release-notes.json $DOCROOT/release-notes.json
sudo chown $OTA_USER $DOCROOT/release-notes.json
sudo chmod 644 $DOCROOT/release-notes.json
python3 -c \"
import plistlib
p = '$DOCROOT/manifest.plist'
d = plistlib.load(open(p, 'rb'))
d['items'][0]['metadata']['bundle-version'] = '$VERSION'
plistlib.dump(d, open('/tmp/manifest.plist', 'wb'))
\"
sudo cp /tmp/manifest.plist $DOCROOT/manifest.plist
rm ~/factotum-publish-ARIA.ipa ~/factotum-publish-release-notes.json
md5sum $DOCROOT/ARIA.ipa
"

DOCROOT_MD5=$($OTA_SSH "md5sum $DOCROOT/ARIA.ipa | awk '{print \$1}'")
if [ "$DOCROOT_MD5" != "$LOCAL_MD5" ]; then
  echo "ERROR: docroot MD5 $DOCROOT_MD5 != local $LOCAL_MD5" >&2
  exit 1
fi
echo "==> docroot MD5 verified: $DOCROOT_MD5"

PUBLIC_VERSION=$($OTA_SSH "curl -s $URL_BASE/release-notes.json | python3 -c \"import json,sys; print(json.load(sys.stdin)['version'])\"")
if [ "$PUBLIC_VERSION" != "$VERSION" ]; then
  echo "ERROR: public release-notes serve version $PUBLIC_VERSION, expected $VERSION" >&2
  exit 1
fi
echo "==> published Factotum $VERSION (build $BUILD) at $URL_BASE/"
