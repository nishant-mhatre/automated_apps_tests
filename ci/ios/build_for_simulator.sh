#!/usr/bin/env bash
# Build an iOS app for the Simulator in CI (plain `xcodebuild build`, ad-hoc signed).
#
#   ci/ios/build_for_simulator.sh <App.xcworkspace> <scheme> [--configuration Debug]
#                                 [--remove-framework Name.xcframework]...
#
# Prints and (on Bitrise) exports BITRISE_APP_DIR_PATH = path of the built .app.
#
# Why not Bitrise's "Xcode Build for Simulator" step: it runs `xcodebuild archive` with
# CODE_SIGNING_ALLOWED=NO, and the Heat app built that way is killed at launch
# ("Code Signature Invalid"). A plain build signs ad-hoc like Xcode's Run does.
#
# --remove-framework drops device-only frameworks from the .xcodeproj on the CI checkout
# before building (see remove_frameworks.rb). The app code must guard their imports with
# `#if canImport(...)`. Never commit the modified project.
set -euo pipefail

[[ $# -ge 2 ]] || { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
WORKSPACE="$1"; SCHEME="$2"; shift 2
CONFIGURATION="Debug"; REMOVE=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)    CONFIGURATION="$2"; shift 2 ;;
    --remove-framework) REMOVE+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
WS_DIR="$(cd "$(dirname "$WORKSPACE")" && pwd)"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # xcodeproj gem needs UTF-8

if [[ ${#REMOVE[@]} -gt 0 ]]; then
  # The app's own project = first .xcodeproj next to the workspace with the same base name.
  PROJECT="$WS_DIR/$(basename "$WORKSPACE" .xcworkspace).xcodeproj"
  [[ -d "$PROJECT" ]] || { echo "Project not found: $PROJECT"; exit 1; }
  # Prefer the app's bundle (fastlane brings xcodeproj); fall back to a user gem install.
  if [[ -f "$WS_DIR/Gemfile" ]] && (cd "$WS_DIR" && bundle exec ruby -e 'require "xcodeproj"' >/dev/null 2>&1); then
    (cd "$WS_DIR" && bundle exec ruby "$HERE/remove_frameworks.rb" "$PROJECT" "${REMOVE[@]}")
  else
    ruby -e 'require "xcodeproj"' >/dev/null 2>&1 || gem install --user-install --no-document xcodeproj
    ruby "$HERE/remove_frameworks.rb" "$PROJECT" "${REMOVE[@]}"
  fi
fi

DERIVED="${DERIVED_DATA_PATH:-${BITRISE_SOURCE_DIR:-$PWD}/build/sim-derived-data}"
set -o pipefail
xcodebuild build \
  -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -skipMacroValidation -skipPackagePluginValidation \
  | { command -v xcpretty >/dev/null && xcpretty || cat; }

APP_PATH="$(find "$DERIVED/Build/Products/$CONFIGURATION-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)"
[[ -d "$APP_PATH" ]] || { echo "Built .app not found under $DERIVED"; exit 1; }
echo "Built app: $APP_PATH ($(lipo -archs "$APP_PATH/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP_PATH/Info.plist")"))"
if command -v envman >/dev/null; then
  envman add --key BITRISE_APP_DIR_PATH --value "$APP_PATH"
fi
