#!/usr/bin/env bash
# PS-03: Sign, notarise, and staple a DMG (or .app) for Gatekeeper approval.
#
# Usage:
#   ./Scripts/notarize.sh <path/to/artifact.dmg>
#
# Required environment variables (set these in your shell or CI secrets):
#   PROMPTLY_DEV_ID_APPLICATION   — e.g. "Developer ID Application: Bit-Pulse AS (TEAMID1234)"
#   PROMPTLY_APPLE_ID             — Apple ID email for notarytool
#   PROMPTLY_TEAM_ID              — Apple Team ID
#   PROMPTLY_NOTARY_PASSWORD      — app-specific password (create at appleid.apple.com)
#   PROMPTLY_ENTITLEMENTS_PLIST   — path to entitlements (defaults to
#                                    PromptShields.MacOS.Widget/Resources/Dev/
#                                    PromptShields.MacOS.Widget.entitlements)
#
# First-time setup:
#   1. Apple Developer Program membership
#   2. Download/install the Developer ID Application certificate from
#      Apple Developer → Certificates
#   3. Create an app-specific password at appleid.apple.com → Sign-In
#      and Security → App-Specific Passwords
#   4. xcrun notarytool store-credentials "promptly-notary" \
#        --apple-id "$PROMPTLY_APPLE_ID" \
#        --team-id "$PROMPTLY_TEAM_ID" \
#        --password "$PROMPTLY_NOTARY_PASSWORD"
#      (Keychain profile alternative to env vars; this script uses env vars.)
#
# What this does:
#   1. Re-signs the artifact with the Developer ID certificate, enabling the
#      hardened runtime. Skip signing the .dmg if it was already signed
#      upstream — only re-sign the .app.
#   2. Submits to Apple's notarisation service via `notarytool submit --wait`.
#   3. On success, staples the ticket into the artifact so it validates
#      offline.
#   4. Runs `spctl --assess` as a final sanity check.

set -euo pipefail

ARTIFACT="${1:?Usage: notarize.sh <path/to/artifact.dmg|app>}"
if [[ ! -e "$ARTIFACT" ]]; then
    echo "error: $ARTIFACT not found" >&2
    exit 1
fi

: "${PROMPTLY_DEV_ID_APPLICATION:?missing PROMPTLY_DEV_ID_APPLICATION env var}"
: "${PROMPTLY_APPLE_ID:?missing PROMPTLY_APPLE_ID env var}"
: "${PROMPTLY_TEAM_ID:?missing PROMPTLY_TEAM_ID env var}"
: "${PROMPTLY_NOTARY_PASSWORD:?missing PROMPTLY_NOTARY_PASSWORD env var}"

ENTITLEMENTS_PLIST="${PROMPTLY_ENTITLEMENTS_PLIST:-PromptShields.MacOS.Widget/Resources/Dev/PromptShields.MacOS.Widget.entitlements}"

extension="${ARTIFACT##*.}"

if [[ "$extension" == "app" ]]; then
    echo "==> codesign (hardened runtime) $ARTIFACT"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_PLIST" \
        --sign "$PROMPTLY_DEV_ID_APPLICATION" \
        --timestamp \
        "$ARTIFACT"
fi

echo "==> notarytool submit $ARTIFACT"
xcrun notarytool submit "$ARTIFACT" \
    --apple-id "$PROMPTLY_APPLE_ID" \
    --team-id "$PROMPTLY_TEAM_ID" \
    --password "$PROMPTLY_NOTARY_PASSWORD" \
    --wait

echo "==> staple"
xcrun stapler staple "$ARTIFACT"

echo "==> verify"
xcrun stapler validate "$ARTIFACT"

if [[ "$extension" == "app" ]]; then
    spctl --assess --type execute --verbose "$ARTIFACT"
elif [[ "$extension" == "dmg" ]]; then
    spctl --assess --type open --context context:primary-signature --verbose "$ARTIFACT"
fi

echo "ok: $ARTIFACT notarised and stapled"
