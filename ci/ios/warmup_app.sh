#!/usr/bin/env bash
# Install and launch an app once on the booted simulator, then quit it.
#
#   ci/ios/warmup_app.sh <App.app> [seconds=60] [simulator udid=booted]
#
# Why: an x86_64-only app runs on Apple Silicon through Rosetta, and the very first launch of
# a new binary is slow while Rosetta translates it. In CI every build is new, so the first
# Maestro flow would time out on the splash. One warm-up launch caches the translation.
set -euo pipefail

APP_PATH="${1:?usage: warmup_app.sh <App.app> [seconds] [udid]}"
SECONDS_TO_WAIT="${2:-60}"
UDID="${3:-booted}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Info.plist")"

if [[ "$UDID" == "booted" ]]; then
  # Wait for a simulator started in the background (e.g. Bitrise "Xcode Start Simulator").
  for _ in $(seq 1 60); do
    xcrun simctl list devices booted | grep -q Booted && break
    sleep 5
  done
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "Warm-up: $BUNDLE_ID for ${SECONDS_TO_WAIT}s"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
sleep "$SECONDS_TO_WAIT"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Warm-up done"
