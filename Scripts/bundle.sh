#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Notch.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Notch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Regenerate the icon from source if it is missing, so a fresh clone builds.
if [ ! -f Resources/AppIcon.icns ]; then
  swift Scripts/make-icon.swift
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# With SIGN_IDENTITY set (e.g. "Developer ID Application: Name (TEAMID)") the
# app is signed for distribution: hardened runtime, a secure timestamp, and the
# entitlements the app needs. Unset, the ad-hoc signature keeps dev builds
# working as before.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp \
    --entitlements Resources/Notch.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "built $APP"
