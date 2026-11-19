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

## CI (Bitrise)

For Heat iOS, `ci/bitrise/heat-ios-e2e.bitrise.yml` has a ready-to-paste workflow
(`Dfanx_Heat_E2E_iOS`), with setup instructions at the top. Its steps:

1. The setup steps of `Dfanx_Heat_dev`, up to "Plist upgrade | Fastlane config". Don't include
   the simulator-stripping steps that `Dfanx_Heat_dev` runs before archiving.
2. **Xcode Start Simulator**: must be an iOS 18.x runtime while the app is x86_64-only.
3. **Script** clones this repo (`E2E_TESTS_REPO` / `E2E_TESTS_REF`).
4. **Script** `ci/ios/build_for_simulator.sh` removes the device-only frameworks and builds;
   it exports `$BITRISE_APP_DIR_PATH`.
5. **Script** `ci/ios/warmup_app.sh` launches the app once.
6. **Maestro Test** with `flow_path: <repo>/heat`, `additional_args: -e APP_ID=…` and
   `exclude_tags: offline`. It publishes to **Test Reports** and adds a zip of the Maestro output.
7. **Deploy to Bitrise.io**.

What the Heat iOS simulator build needs, and why:

| Problem | Handled by |
|---|---|
| `HeatWayfinding.xcframework` and the Unity export (`UnityFramework`) are device-only | `build_for_simulator.sh --remove-framework …` removes them from the project on the CI machine; `WayfindingView.swift` guards them with `#if canImport` |
| Bitrise's "Xcode Build for Simulator" step archives without signing, and that app is killed at launch ("Code Signature Invalid") | Plain `xcodebuild build` (ad-hoc signed) in `build_for_simulator.sh` |
| The app is x86_64-only, and the first launch of a new binary under Rosetta is slow enough to time out the splash | `warmup_app.sh` launches it once; iOS 18.x simulator (iOS 26 can't run x86_64 apps) |

`ci/bitrise/ios_e2e.sh <app> <App.app>` does steps 2, 5, 6 and 7 in a single script
(create and boot a simulator, warm up, run, publish). Use it for local CI-style runs or on a CI
other than Bitrise.

Ways to trigger it: a Pipeline that runs it alongside `Dfanx_Heat_dev`, a nightly Scheduled
build, or a PR trigger. It takes roughly 15–20 min, mostly the build.

## Heat: what's covered

| Flow | Tags | What it checks |
|---|---|---|
| `splash/splash_cold_launch.yaml` | splash, smoke | Fresh install shows the RN splash and its background, then routes to EULA/onboarding (not home) |
| `splash/splash_relaunch.yaml` | splash | Cold relaunch shows the splash again and lands on the same screen as the first launch |
| `splash/splash_error_retry.yaml` | splash, offline | Offline launch shows NO CONNECTION / WE HIT A SNAG; TRY AGAIN while offline doesn't crash; on Android it also checks recovery once the network is back |
| `onboarding/splash_to_home.yaml` | onboarding, smoke | New user: Splash → EULA (Accept) → onboarding (Continue, allow notifications, skip Ticketmaster, Next on NBA ID) → Home tab |
| `onboarding/returning_user_lands_home.yaml` | onboarding | After finishing onboarding, a cold relaunch goes Splash → Home with no EULA/onboarding |
| `onboarding/eula_decline.yaml` | onboarding | Declining the EULA shows the "accept to continue" modal and keeps the user on the EULA; accepting afterwards continues to onboarding |

Shared steps in `heat/common/`: `launch_fresh`, `assert_splash_visible`, `assert_left_splash`,
`accept_eula`, `complete_onboarding` (taps each step's skip/next button, or continue if it has
none, so CMS changes to the steps don't break it), `allow_notifications_prompt` and `assert_home`.
No flow signs in to Ticketmaster or NBA ID.

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
