#!/usr/bin/env bash
# Run an app's Maestro flows on iOS or Android.
#
#   scripts/run.sh <app> <ios|android> [--env dev|preview|prod] [extra maestro test args...]
#
# Examples:
#   scripts/run.sh heat ios
#   scripts/run.sh heat android --env preview
#   scripts/run.sh heat ios --include-tags=offline           # iOS offline flow (network off first)
#   scripts/run.sh heat android heat/splash/splash_relaunch.yaml
#
# Env overrides: DEVICE=<udid|serial> picks the device; OUTPUT_DIR sets the report folder.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[[ $# -ge 2 ]] || usage

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"; PLATFORM="$(echo "$2" | tr '[:upper:]' '[:lower:]')"; shift 2
ENV_NAME="dev"
if [[ "${1:-}" == "--env" ]]; then ENV_NAME="$2"; shift 2; fi

APP_DIR="$ROOT/$APP"
[[ -d "$APP_DIR" ]] || { echo "No app folder: $APP_DIR"; exit 1; }
[[ "$PLATFORM" == "ios" || "$PLATFORM" == "android" ]] || usage

APP_ID="$(grep -E "^${PLATFORM}_${ENV_NAME}=" "$APP_DIR/app_ids.conf" | cut -d= -f2- || true)"
[[ -n "$APP_ID" ]] || { echo "No ${PLATFORM}_${ENV_NAME} entry in $APP_DIR/app_ids.conf"; exit 1; }

# Maestro needs Java 17+. Use Homebrew's keg-only openjdk@17 if nothing else is set up.
if ! java -version >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/openjdk@17 ]]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@17
  export PATH="$JAVA_HOME/bin:$PATH"
fi
export PATH="$HOME/.maestro/bin:$PATH"
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
command -v maestro >/dev/null || { echo "maestro not found - see README.md#setup"; exit 1; }

# Pick a device of the right platform so maestro doesn't prompt when both are running.
if [[ -z "${DEVICE:-}" ]]; then
  if [[ "$PLATFORM" == "ios" ]]; then
    DEVICE="$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1 || true)"
  else
    ADB="$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")"
    DEVICE="$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}' || true)"
  fi
  [[ -n "$DEVICE" ]] || { echo "No booted $PLATFORM device/simulator found."; exit 1; }
fi

# The offline flow is manual on iOS (no network control); skip it unless asked for.
EXTRA=()
if [[ "$PLATFORM" == "ios" && "$*" != *offline* ]]; then EXTRA+=(--exclude-tags=offline); fi

# Default target is the whole app folder unless a flow file/folder was passed.
TARGET=("$APP_DIR")
for a in "$@"; do [[ "$a" == *.yaml || -d "$a" ]] && TARGET=() && break; done

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/reports/$APP/$PLATFORM/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT_DIR"

echo "App: $APP ($PLATFORM/$ENV_NAME) id=$APP_ID device=$DEVICE"
echo "Reports: $OUTPUT_DIR"
exec maestro --device "$DEVICE" test \
  -e APP_ID="$APP_ID" \
  --format junit --output "$OUTPUT_DIR/report.xml" \
  --test-output-dir "$OUTPUT_DIR" \
  ${EXTRA[@]+"${EXTRA[@]}"} "$@" ${TARGET[@]+"${TARGET[@]}"}
