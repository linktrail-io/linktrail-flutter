# Testing

## Unit tests and analysis

```sh
flutter analyze
flutter test
```

## E2E smoke tests (Maestro)

`e2e/run.sh` builds the example app from this checkout (the plugin is a path dependency) with the
E2E panel switched on (`--dart-define=E2E=true`), installs it and runs the Maestro flows in
`e2e/flows/`. The same flows run on Android and iOS.

| Flow | Needs | Checks |
| --- | --- | --- |
| `consent_allow` | nothing | the consent sheet commits "Allow tracking" |
| `consent_deny` | nothing | the consent sheet commits "Deny"; no link is delivered |
| `deferred_allow` | `LINKTRAIL_KEY` | a real click, then a fresh install and allow: `onLink` fires exactly once, `source: deferred`, a `/products/…` path and `voucher=SUMMER25` in `customData`. Then the backend check: recorded, attributed, `click_token`, 1 install |
| `deferred_deny` | `LINKTRAIL_KEY` | a real click, then deny: no `onLink`. Then the backend check: not recorded, 0 installs |
| `reengagement` | `LINKTRAIL_KEY` | allow, then a campaign link arrives: `onLink` fires once with `source: reengagement` |
| `track_event` | `LINKTRAIL_KEY` | allow, then `trackEvent("e2e_purchase", value: 9.99, currency: "USD")` succeeds |

How the deferred click is staged:

- **Android:** the script makes a real click with an Android Chrome user agent, takes `lt_click`
  from the Play Store redirect and stages it with the native SDK's debug fake referrer
  (`adb shell setprop debug.linktrail.referrer "lt_click=<token>"`). The override ships in the
  native Android SDK after 0.0.5, so while the plugin pins 0.0.5 the Android deferred flows are
  skipped with a warning (`ANDROID_FAKE_REFERRER=1` forces them).
- **iOS:** `e2e/flows/ios/safari_click.yaml` opens the link in Safari, the interstitial puts the
  token on the clipboard, and the deferred flow taps the native Paste button.

On iOS the re-engagement link goes through `LinkTrail.handleDeepLink` from the E2E panel, because an
unsigned simulator build has no associated domains. On Android it is a real https App Link.

### Run locally

```sh
# Android: a booted emulator or device
bash e2e/run.sh android                       # all flows
bash e2e/run.sh android consent_deny          # one flow

# iOS: a booted simulator (or DEVICE=<udid>)
bash e2e/run.sh ios
```

Without `LINKTRAIL_KEY` only the consent flows run. To run the real flows, export `LINKTRAIL_KEY`
(and `E2E_TOKEN` for the backend check) in your shell. The script passes the key to the build
through a private temp file and never prints either secret. The real flows make real clicks on
`LINK_URL` (default `https://kick.linktrail.io/discounted-product`), so run them sparingly.

### CI

`.github/workflows/e2e.yml` runs on every pull request and on manual dispatch:

- **Native SDK versions:** `scripts/check-native-versions.py` compares the pinned `LinkTrailSDK`
  (podspec and Package.swift) and `io.linktrail:sdk` with the latest on CocoaPods trunk and Maven
  Central. It only warns for now; set the repository variable `NATIVE_VERSION_CHECK_STRICT=true`
  to make an outdated pin fail.
- **Android:** an API 35 emulator on `ubuntu-latest` with KVM.
- **iOS:** the self-hosted Mac (`[self-hosted, macOS]`), behind the machine-wide simulator lock
  (`e2e/sim-lock.sh`, shared with the iOS SDK's e2e). Fork pull requests never run on it.

Repository secrets: `LINKTRAIL_KEY` and `E2E_TOKEN`. When they are missing (for example on a fork
pull request) the real flows are skipped with a notice.

The backend check needs the app ids in the backend's `E2E_APP_IDENTIFIERS`: `io.linktrail.example`
(Android) and `io.linktrail.kickflipdemo` (iOS).
