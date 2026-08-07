#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Notch.app"
DMG="build/Notch.dmg"
STAGE="build/dmg"

if [ ! -d "$APP" ]; then
  echo "missing $APP — run ./Scripts/bundle.sh first" >&2
  exit 1
fi

# Classic drag-to-install layout: the app beside a symlink to /Applications.
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Notch.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname Notch \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"

# Sign the DMG itself when a distribution identity is set (same variable as
# bundle.sh); unsigned DMGs are fine for local use.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
echo "built $DMG"
