#!/usr/bin/env bash
# PS-01: Build a branded drag-to-Applications DMG for release.
#
# Usage:
#   ./Scripts/build-dmg.sh <path/to/Promptly.app> <version>
#
# Requirements (install once):
#   brew install create-dmg
#
# Assets expected under Scripts/dmg-assets/ (gitignored):
#   background.png   — 580x400 branded background (navy gradient + tagline)
#   volume-icon.icns — Finder icon for the mounted volume
#
# Output: ./dist/Promptly-<version>-macos-<arch>.dmg

set -euo pipefail

APP_PATH="${1:?Usage: build-dmg.sh <path/to/Promptly.app> <version>}"
VERSION="${2:?Usage: build-dmg.sh <path/to/Promptly.app> <version>}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found at $APP_PATH" >&2
    exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="intel"
fi

DIST_DIR="$(cd "$(dirname "$0")/.." && pwd)/dist"
mkdir -p "$DIST_DIR"

DMG_NAME="Promptly-${VERSION}-macos-${ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

ASSETS_DIR="$(cd "$(dirname "$0")" && pwd)/dmg-assets"

BACKGROUND_FLAG=()
if [[ -f "$ASSETS_DIR/background.png" ]]; then
    BACKGROUND_FLAG=(--background "$ASSETS_DIR/background.png")
fi

VOLUME_ICON_FLAG=()
if [[ -f "$ASSETS_DIR/volume-icon.icns" ]]; then
    VOLUME_ICON_FLAG=(--volicon "$ASSETS_DIR/volume-icon.icns")
fi

# 580x400 per PS-01 acceptance criteria.
create-dmg \
    --volname "Promptly" \
    "${VOLUME_ICON_FLAG[@]}" \
    "${BACKGROUND_FLAG[@]}" \
    --window-pos 200 120 \
    --window-size 580 400 \
    --icon-size 100 \
    --icon "$(basename "$APP_PATH")" 140 200 \
    --app-drop-link 440 200 \
    --hide-extension "$(basename "$APP_PATH")" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

echo "built: $DMG_PATH"
echo "next:  ./Scripts/notarize.sh \"$DMG_PATH\""
