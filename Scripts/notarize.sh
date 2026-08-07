#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="${1:-build/Notch.dmg}"

if [ ! -f "$DMG" ]; then
  echo "missing $DMG — run ./Scripts/make-dmg.sh first" >&2
  exit 1
fi

# Credentials, one of:
#   NOTARY_PROFILE       a `xcrun notarytool store-credentials` keychain profile
#                        (handy locally)
#   APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER_ID
#                        an App Store Connect API key (what CI uses)
if [ -n "${NOTARY_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ]; then
  AUTH=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
else
  echo "set NOTARY_PROFILE, or APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER_ID" >&2
  exit 1
fi

# Submit and wait. notarytool's exit code alone is not trusted — the JSON
# status is checked explicitly, and on anything but Accepted the full
# notarization log is fetched so the failure is diagnosable from CI output.
set +e
SUBMISSION="$(xcrun notarytool submit "$DMG" --wait --output-format json "${AUTH[@]}" 2>&1)"
SUBMIT_EXIT=$?
set -e
echo "$SUBMISSION"

ID="$(echo "$SUBMISSION" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)"
STATUS="$(echo "$SUBMISSION" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)"

if [ "$SUBMIT_EXIT" -ne 0 ] || [ "$STATUS" != "Accepted" ]; then
  echo "notarization failed (status: ${STATUS:-unknown})" >&2
  if [ -n "$ID" ]; then
    xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
  fi
  exit 1
fi

xcrun stapler staple "$DMG"
echo "notarized and stapled $DMG"
