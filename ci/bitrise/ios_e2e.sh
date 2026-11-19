#!/usr/bin/env bash
# Run an app's Maestro flows on an iOS Simulator in CI (Bitrise, but works anywhere on macOS).
#
#   ci/bitrise/ios_e2e.sh <app> <path/to/App.app> [--env dev|preview|prod] [extra run.sh args...]
#
# What it does:
#   1. creates + boots a fresh iPhone simulator (newest iOS runtime installed)
#   2. installs the .app built for the simulator
#   3. installs Maestro if missing (pin with MAESTRO_VERSION)
#   4. runs scripts/run.sh with a JUnit report
#   5. on Bitrise: publishes the JUnit report to Test Reports and zips screenshots/logs
#      into $BITRISE_DEPLOY_DIR (the Deploy to Bitrise.io step uploads both)
#
# Env:
#   SIM_DEVICE_TYPE  simulator model to create (default: newest "iPhone NN Pro" available)
#   MAESTRO_VERSION  e.g. 2.12.1 (default: latest)
set -euo pipefail

[[ $# -ge 2 ]] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
APP="$1"; APP_PATH="$2"; shift 2
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -d "$APP_PATH" ]] || { echo "App bundle not found: $APP_PATH"; exit 1; }

# --- 1. Simulator --------------------------------------------------------------------
# iOS 26+ simulators can't run x86_64-only apps (Rosetta). Heat currently excludes arm64 for
# the simulator, so for such builds pick the newest runtime below 26. Override with SIM_MAX_IOS.
APP_BIN="$APP_PATH/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP_PATH/Info.plist")"
APP_ARCHS="$(lipo -archs "$APP_BIN")"
MAX_IOS="${SIM_MAX_IOS:-}"
if [[ -z "$MAX_IOS" && " $APP_ARCHS " != *" arm64 "* ]]; then MAX_IOS=25; fi
echo "App archs: $APP_ARCHS${MAX_IOS:+ -> using iOS runtime <= $MAX_IOS}"

RUNTIME="$(xcrun simctl list runtimes available -j | MAX_IOS="$MAX_IOS" python3 -c '
import json,os,sys
mx=os.environ.get("MAX_IOS")
rs=[r for r in json.load(sys.stdin)["runtimes"] if r["platform"]=="iOS" and r.get("isAvailable")]
if mx: rs=[r for r in rs if int(r["version"].split(".")[0]) <= int(mx)]
rs.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')"
[[ -n "$RUNTIME" ]] || { echo "No suitable iOS simulator runtime installed${MAX_IOS:+ (need iOS <= $MAX_IOS for an x86_64-only app)}"; exit 1; }

# Newest "iPhone NN Pro" that this runtime supports.
DEVICE_TYPE="${SIM_DEVICE_TYPE:-$(xcrun simctl list runtimes available -j | RUNTIME="$RUNTIME" python3 -c '
import json,os,re,sys
rt=[r for r in json.load(sys.stdin)["runtimes"] if r["identifier"]==os.environ["RUNTIME"]][0]
ts=[t for t in rt.get("supportedDeviceTypes",[]) if re.fullmatch(r"iPhone \d+ Pro", t["name"])]
ts.sort(key=lambda t: int(re.search(r"\d+", t["name"]).group()))
print(ts[-1]["identifier"] if ts else "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro")')}"

UDID="$(xcrun simctl create "maestro-e2e-$APP" "$DEVICE_TYPE" "$RUNTIME")"
echo "Simulator: $UDID ($DEVICE_TYPE, $RUNTIME)"
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
# Installs the app and launches it once so Rosetta's first-launch translation isn't timed by a flow.
"$ROOT/ci/ios/warmup_app.sh" "$APP_PATH" "${WARMUP_SECONDS:-60}" "$UDID"

# --- 2. Maestro ----------------------------------------------------------------------
export PATH="$HOME/.maestro/bin:$PATH"
if ! command -v maestro >/dev/null; then
  echo "Installing Maestro ${MAESTRO_VERSION:-latest}"
  curl -fsSL "https://get.maestro.mobile.dev" | MAESTRO_VERSION="${MAESTRO_VERSION:-}" bash
fi
# CI machines start the XCTest driver slowly; give it more time than the default.
export MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-180000}"

# --- 3. Run --------------------------------------------------------------------------
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/reports/$APP/ios/ci-$(date +%Y%m%d-%H%M%S)}"
STATUS=0
DEVICE="$UDID" OUTPUT_DIR="$OUTPUT_DIR" "$ROOT/scripts/run.sh" "$APP" ios --report junit "$@" || STATUS=$?

# --- 4. Publish to Bitrise -----------------------------------------------------------
if [[ -n "${BITRISE_TEST_RESULT_DIR:-}" && -f "$OUTPUT_DIR/report.xml" ]]; then
  RESULT_DIR="$BITRISE_TEST_RESULT_DIR/maestro-$APP-ios"
  mkdir -p "$RESULT_DIR"
  cp "$OUTPUT_DIR/report.xml" "$RESULT_DIR/report.xml"
  printf '{"test-name":"Maestro E2E - %s iOS"}\n' "$APP" > "$RESULT_DIR/test-info.json"
fi
if [[ -n "${BITRISE_DEPLOY_DIR:-}" ]]; then
  (cd "$(dirname "$OUTPUT_DIR")" && zip -qr "$BITRISE_DEPLOY_DIR/maestro-$APP-ios-artifacts.zip" "$(basename "$OUTPUT_DIR")")
fi

exit "$STATUS"
