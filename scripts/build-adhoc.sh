#!/bin/bash
# build-adhoc.sh — Ad Hoc release lane for Factotum iOS (primary distribution lane per the author's Oct 17, 2026 decision).
# Archives the ARIA scheme and exports an Ad Hoc (release-testing) IPA into build/adhoc/.
# Signing uses the same throwaway-keychain pattern as scripts/release.sh: the Apple Distribution
# cert is fetched from AWS Secrets Manager (example/apple-distribution-cert) and imported into a
# temporary keychain, because codesign with the Distribution identity fails with
# errSecInternalComponent from non-GUI sessions when it relies on the login keychain.
# Provisioning: automatic signing with -allowProvisioningUpdates lets Xcode mint the Ad Hoc
# profiles via the developer portal (PLA-governed; independent of App Store Connect agreements).
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_KEYCHAIN="$(mktemp -dt sign-keychain).keychain-db"
SIGN_P12="$(mktemp -t sign-p12-XXXX).p12"
SIGN_KEYCHAIN_PASS="$(/usr/bin/openssl rand -hex 16)"
cleanup() {
  security delete-keychain "$SIGN_KEYCHAIN" 2>/dev/null || true
  rm -f "$SIGN_P12"
  security list-keychains -d user -s login.keychain-db 2>/dev/null || true
}
trap cleanup EXIT

echo "==> fetching Apple Distribution cert from vault"
SIGN_VAULT_JSON=$(aws secretsmanager get-secret-value \
  --secret-id example/apple-distribution-cert \
  --profile "${AWS_PROFILE:-secrets}" \
  --region "${AWS_REGION:-us-east-1}" \
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

mkdir -p build
ARCHIVE=build/Factotum-3.1.0-141.xcarchive
echo "==> archive (ad hoc lane)"
xcodebuild archive -scheme ARIA \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  OTHER_CODE_SIGN_FLAGS="--keychain $SIGN_KEYCHAIN"
echo "==> export ad hoc ipa"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions-AdHoc.plist \
  -exportPath build/adhoc \
  -allowProvisioningUpdates \
  OTHER_CODE_SIGN_FLAGS="--keychain $SIGN_KEYCHAIN"
echo "==> done"
ls -la build/adhoc/
