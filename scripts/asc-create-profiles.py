#!/usr/bin/env python3
"""
Create user-managed App Store distribution profiles via the App Store
Connect REST API for ARIA's embedded targets (Share, Widgets, Watch).

The main app target uses "ARIA iOS Distribution" — created manually
in the dev portal long ago. The 3 embedded targets only had auto-generated
"Xcode managed" profiles, which xcodebuild rejects when CODE_SIGN_STYLE=Manual.
This script mints proper user-managed profiles for them.

Auth uses the same .p8 / key-id / issuer-id triple that release.sh's
upload step uses (the .p8 key named by ASC_KEY_ID, from your vault).

Self-contained: no pip deps. Shells out to /usr/bin/openssl for ES256
JWT signing, parses the DER output to JOSE r||s in pure Python.

Capabilities: each target's required App Groups are read from its
.entitlements file in this repo. The script enables the APP_GROUPS capability
on the bundle ID when it is missing, regenerates a profile that App Store
Connect reports as non-ACTIVE (enabling a capability invalidates existing
profiles), and verifies every saved profile actually carries the required
groups. Assigning a specific group to an App ID is not exposed by the ASC API:
if a profile still lacks a group after regeneration, the script says which
portal step is missing and exits non-zero.

Usage on the build Mac:
    python3 scripts/asc-create-profiles.py
    python3 scripts/asc-create-profiles.py --regenerate   # force re-mint all 3
"""
import base64
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_BASE = "https://api.appstoreconnect.apple.com/v1"

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
KEY_PATH = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"

PROFILES_DIR = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"

REPO_ROOT = Path(__file__).resolve().parent.parent

APP_GROUPS_KEY = "com.apple.security.application-groups"

# bundle_id → desired profile name (matches the sibling project's naming) → the
# target's entitlements file (source of the App Groups the profile must carry)
TARGETS = [
    ("com.example.factotum.share",       "ARIA iOS Share Distribution",   "ShareExtension/ShareExtension.entitlements"),
    ("com.example.factotum.widgets",     "ARIA iOS Widgets Distribution", "ARIAWidgets/ARIAWidgets.entitlements"),
    ("com.example.factotum.watchkitapp", "ARIA iOS Watch Distribution",   "ARIAWatch/ARIAWatch.entitlements"),
]


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_jose(der: bytes) -> bytes:
    # ECDSA DER: SEQUENCE { INTEGER r, INTEGER s }. JOSE wants raw r||s,
    # each padded to 32 bytes for P-256.
    if der[0] != 0x30:
        raise ValueError("not a DER SEQUENCE")
    if der[1] & 0x80:
        n = der[1] & 0x7F
        body = der[2 + n:]
    else:
        body = der[2:]
    if body[0] != 0x02:
        raise ValueError("expected INTEGER for r")
    rlen = body[1]
    r = body[2:2 + rlen]
    s_part = body[2 + rlen:]
    if s_part[0] != 0x02:
        raise ValueError("expected INTEGER for s")
    slen = s_part[1]
    s = s_part[2:2 + slen]
    # DER prefixes a 0x00 to make integers unambiguously positive — strip
    if len(r) > 32:
        r = r[-32:]
    if len(s) > 32:
        s = s[-32:]
    return r.rjust(32, b"\x00") + s.rjust(32, b"\x00")


def make_jwt() -> str:
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {
        "iss": ISSUER_ID,
        "iat": int(time.time()),
        "exp": int(time.time()) + 1200,  # 20 min, ASC's documented max
        "aud": "appstoreconnect-v1",
    }
    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    msg = f"{h}.{p}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(KEY_PATH)],
        input=msg, capture_output=True, check=True,
    ).stdout
    sig = der_to_jose(der)
    return f"{h}.{p}.{b64url(sig)}"


def asc(token: str, method: str, path: str, body: dict | None = None) -> dict:
    url = API_BASE + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}  # DELETE → 204 No Content
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP {e.code} {method} {path}\n{e.read().decode()}\n")
        raise


def required_app_groups(entitlements_rel: str) -> list[str]:
    """App Groups the target requests in its .entitlements file."""
    with open(REPO_ROOT / entitlements_rel, "rb") as f:
        return list(plistlib.load(f).get(APP_GROUPS_KEY, []))


def profile_app_groups(profile_bytes: bytes) -> list[str]:
    """App Groups granted by a .mobileprovision (a CMS envelope around an XML plist)."""
    start = profile_bytes.find(b"<?xml")
    end = profile_bytes.find(b"</plist>")
    if start < 0 or end < 0:
        raise ValueError("no embedded plist in profile")
    plist = plistlib.loads(profile_bytes[start:end + len(b"</plist>")])
    return list(plist.get("Entitlements", {}).get(APP_GROUPS_KEY, []))


def ensure_app_groups_capability(token: str, bundle_resource_id: str) -> None:
    caps = asc(token, "GET", f"/bundleIds/{bundle_resource_id}/bundleIdCapabilities")
    if any(c["attributes"].get("capabilityType") == "APP_GROUPS" for c in caps.get("data", [])):
        return
    asc(token, "POST", "/bundleIdCapabilities", body={
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "APP_GROUPS"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}}},
        }
    })
    print("  enabled APP_GROUPS capability on the bundle ID (existing profiles are now invalid)")


def main() -> int:
    regenerate = "--regenerate" in sys.argv[1:]
    missing_groups: list[tuple[str, list[str]]] = []

    if not KEY_PATH.exists():
        print(f"ERROR: ASC key not found at {KEY_PATH}", file=sys.stderr)
        return 1

    token = make_jwt()

    # Find the Apple Distribution cert once (all 3 profiles use it).
    cert_resp = asc(token, "GET", "/certificates?filter[certificateType]=DISTRIBUTION")
    if not cert_resp["data"]:
        print("ERROR: no DISTRIBUTION certificate found in the team", file=sys.stderr)
        return 1
    # Pick the first non-expired one
    now = time.time()
    valid_certs = [
        c for c in cert_resp["data"]
        if time.mktime(time.strptime(c["attributes"]["expirationDate"][:19], "%Y-%m-%dT%H:%M:%S")) > now
    ]
    if not valid_certs:
        print("ERROR: no non-expired DISTRIBUTION cert", file=sys.stderr)
        return 1
    cert = valid_certs[0]
    cert_id = cert["id"]
    print(f"==> using cert {cert['attributes']['name']} (id={cert_id}, expires {cert['attributes']['expirationDate']})")

    PROFILES_DIR.mkdir(parents=True, exist_ok=True)

    for bundle_id, profile_name, entitlements_rel in TARGETS:
        print()
        print(f"=== {bundle_id} → {profile_name!r} ===")

        bundle_resp = asc(token, "GET", f"/bundleIds?filter[identifier]={urllib.parse.quote(bundle_id)}")
        if not bundle_resp["data"]:
            print(f"  ERROR: bundle ID {bundle_id} not registered", file=sys.stderr)
            return 1
        bundle_resource_id = bundle_resp["data"][0]["id"]

        wanted_groups = required_app_groups(entitlements_rel)
        if wanted_groups:
            ensure_app_groups_capability(token, bundle_resource_id)

        existing = asc(token, "GET", f"/profiles?filter[name]={urllib.parse.quote(profile_name)}")
        active = [p for p in existing["data"] if p["attributes"].get("profileState") == "ACTIVE"]
        prof = None
        if active and not regenerate:
            prof = active[0]
            print(f"  profile already exists (id={prof['id']}, uuid={prof['attributes']['uuid']}, state=ACTIVE)")
        else:
            # Non-ACTIVE (INVALID after a capability change) or --regenerate:
            # delete server-side and locally so Xcode never resolves the stale
            # copy by name, then mint a fresh one below.
            for stale in existing["data"]:
                attrs = stale["attributes"]
                print(f"  deleting profile id={stale['id']} uuid={attrs['uuid']} state={attrs.get('profileState')}")
                asc(token, "DELETE", f"/profiles/{stale['id']}")
                (PROFILES_DIR / f"{attrs['uuid']}.mobileprovision").unlink(missing_ok=True)
        if prof is None:
            create_body = {
                "data": {
                    "type": "profiles",
                    "attributes": {
                        "name": profile_name,
                        "profileType": "IOS_APP_STORE",
                    },
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                        "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
                    },
                }
            }
            resp = asc(token, "POST", "/profiles", body=create_body)
            prof = resp["data"]
            print(f"  created (id={prof['id']}, uuid={prof['attributes']['uuid']})")

        # profileContent is base64-encoded .mobileprovision bytes
        content_b64 = prof["attributes"].get("profileContent")
        if not content_b64:
            full = asc(token, "GET", f"/profiles/{prof['id']}")
            content_b64 = full["data"]["attributes"]["profileContent"]
        profile_bytes = base64.b64decode(content_b64)
        uuid = prof["attributes"]["uuid"]
        out = PROFILES_DIR / f"{uuid}.mobileprovision"
        out.write_bytes(profile_bytes)
        os.chmod(out, 0o600)
        print(f"  saved {out}")

        granted = profile_app_groups(profile_bytes)
        lacking = [g for g in wanted_groups if g not in granted]
        if lacking:
            print(f"  ERROR: profile lacks App Group(s) {lacking} requested by {entitlements_rel}", file=sys.stderr)
            missing_groups.append((bundle_id, lacking))
        elif wanted_groups:
            print(f"  verified App Groups {wanted_groups}")

    print()
    if missing_groups:
        print("==> some profiles do not carry the App Groups their targets request.", file=sys.stderr)
        print("    The ASC API cannot assign a group to an App ID. In the developer portal:", file=sys.stderr)
        for bundle_id, lacking in missing_groups:
            print(f"      Identifiers → {bundle_id} → App Groups → Configure → select {', '.join(lacking)} → Save", file=sys.stderr)
        print("    then re-run this script (the edit invalidates the profile, so it is re-minted).", file=sys.stderr)
        return 1
    print("==> all profiles created/synced")
    return 0


if __name__ == "__main__":
    sys.exit(main())
