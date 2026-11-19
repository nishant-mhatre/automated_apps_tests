# automated_apps_tests

End-to-end UI tests for our mobile apps, written with [Maestro](https://maestro.mobile.dev).
The same flow files run on **iOS and Android**. Each app has its own folder, and platform
differences are handled inside the flows with `runFlow: when: platform:`.

```
<app>/                 # one folder per app (e.g. heat/)
  config.yaml          # which flows belong to the workspace
  app_ids.conf         # bundle id / application id per platform + env
  common/              # reusable sub-flows (launch, shared assertions)
  <feature>/           # flows grouped by feature (e.g. splash/)
scripts/run.sh         # runner: picks APP_ID + device, writes reports
reports/               # run output (git-ignored)
```

## Setup

1. **Java 17+**: `brew install openjdk@17` (`scripts/run.sh` finds it even though it's keg-only).
2. **Maestro**:
   ```bash
   curl -fsSL "https://get.maestro.mobile.dev" | bash
   ```
   or download `maestro.zip` from the [GitHub releases](https://github.com/mobile-dev-inc/maestro/releases)
   and unzip it into `~/.maestro`.
3. **A device with the app installed**
   - iOS: boot a simulator and `xcrun simctl install booted <path>/MiamiHeat.app`
     (Debug-iphonesimulator build from Xcode DerivedData).
   - Android: start an emulator and `adb install -r -g app-dev-debug.apk`.

## Running

```bash
scripts/run.sh heat ios                       # all Heat flows on the booted simulator
scripts/run.sh heat android                   # all Heat flows on the connected emulator/device
scripts/run.sh heat android --env preview     # other app ids from heat/app_ids.conf
scripts/run.sh heat ios heat/splash/splash_relaunch.yaml   # a single flow
scripts/run.sh heat android --include-tags=smoke           # by tag
DEVICE=<udid|serial> scripts/run.sh heat ios  # pick a specific device
```

## Reports

Every run writes to `reports/<app>/<platform>/<timestamp>/`. `reports/<app>/<platform>/latest`
always points at the newest run.

```bash
scripts/run.sh heat ios --open                # HTML report (default), opened in the browser when done
scripts/run.sh heat android --report junit    # JUnit XML for CI
open reports/heat/ios/latest/report.html      # reopen the last iOS report
```

| Option | File | Use for |
|---|---|---|
| `--report html` (default) | `report.html` | Reading results: each flow and every step with its status |
| `--report junit` | `report.xml` | CI test tabs (Bitrise, GitHub Actions, Jenkins) |

The same folder also has, for each flow, `screenshots/` (from `takeScreenshot` and failures),
`screen-hierarchy/` (the element tree at a failure, useful for finding ids), `commands.json`
and `logs/maestro.log`.

Open Maestro Studio to inspect elements and try out commands:
```bash
maestro studio
```

## Heat: what's covered

| Flow | Tags | What it checks |
|---|---|---|
| `splash/splash_cold_launch.yaml` | splash, smoke | Fresh install shows the RN splash and its background, then routes to EULA/onboarding (not home) |
| `splash/splash_relaunch.yaml` | splash | Cold relaunch shows the splash again and lands on the same screen as the first launch |
| `splash/splash_error_retry.yaml` | splash, offline | Offline launch shows NO CONNECTION / WE HIT A SNAG; TRY AGAIN while offline doesn't crash; on Android it also checks recovery once the network is back |

**Offline flow on iOS:** Maestro can't control Simulator networking, so `run.sh` skips
`offline`-tagged flows on iOS. To run it, turn off the Mac's network and then run
`scripts/run.sh heat ios --include-tags=offline`. On Android it runs automatically, using airplane mode.

## Writing flows

- **Use `id:` selectors for RN screens.** A React Native `testID` shows up as `id` on both
  platforms. The DFanX bundle already has testIDs (`splash-screen*`, `onboarding-*`, `bottom-nav*`, …).
  For native screens use the accessibility identifier (iOS), resource-id or `testTag` (Android), or visible text.
- **Never hard-code an app id.** Use `appId: ${APP_ID}` and let `run.sh` set it.
- **Platform-specific steps** go inside `runFlow: when: platform: iOS|Android`.
  Example: iOS location permission is `inuse/always/never`, Android's is `allow/deny`.
- **Leave the device clean.** Any flow that changes device state (airplane mode, etc.) must restore it in `onFlowComplete`.
- **Use generous timeouts on iOS.** Reading the view hierarchy while Lottie animations play is slow, so wait 30–40s for things that appear during the splash.

## Known issues

- **Android debug builds pointing at a local DFanX (`localhost:3000`):** the RN splash can't fetch
  its content, so it stays on `dfanx-splash-blank` and the cold-launch and relaunch flows fail.
  Either run the local DFanX API and forward the port (`adb reverse tcp:3000 tcp:3000`), or use a
  build that points at the dev environment.
