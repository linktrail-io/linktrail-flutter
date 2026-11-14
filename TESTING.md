# Testing

## Unit tests and analysis

```sh
flutter analyze
flutter test
```

## E2E tests (Maestro)

`e2e/run.sh` builds the example app from this checkout (the plugin is a path dependency) with the
E2E panel switched on (`--dart-define=E2E=true`), installs it and runs the Maestro rows. The rows are
the native SDKs' e2e rows, run through the plugin, on Android and iOS alike. Everything is
data-driven, as in the native repos:

- `e2e/e2e-env.json`: the one table of hosts, slugs and backend URLs per environment (`prod`, the
  default, and `dev`), the link-type links, the reward links and which newer backend checks each
  environment has deployed. No flow or script names a host or slug.
- `e2e/e2e-flows.json`: the one table of rows, in run order.
- `e2e/e2e-env.py`: resolves both with the run's choices into the plan (`plan`) and the values
  (`resolve`); a bad choice fails before the build.
- `e2e/e2e-verify.py`: the backend rules, used by `e2e/verify.sh` to poll the private verify endpoint
  for the row's own click.

A link type or reward link the environment has no link for is **skipped with a notice**, never
failed (on prod: `e2e-event`, the per_event link). A row whose app steps pass but whose backend check
can't run (no `E2E_TOKEN`, or a `backend_checks` toggle off) is reported as **skipped** with the reason,
never as a pass.

| Row | Link (slot) | Checks |
| --- | --- | --- |
| `consent_allow` | none | the consent sheet commits "Allow tracking" |
| `consent_deny` | none | the consent sheet commits "Deny"; no link is delivered |
| `deferred_subdomain_allow` | `subdomain_link` | real click, token staged, fresh install, allow: `onLink` once, `source: deferred`, `/products/aj1`, `voucher=SUMMER25`. Backend: recorded, attributed, `click_token`, 1 install, not fraud |
| `deferred_subdomain_deny` | `subdomain_link` | real click, deny: no `onLink`, no attribution. Backend: not recorded, 0 installs |
| `deferred_custom_allow` / `_deny` | `custom_link` | the same on the custom domain |
| `deferred_custom_allow__<type>` | link type's link | as `deferred_custom_allow`, plus `customData` `linkType=<type>` and `source=e2e`; backend `linkType`, and the reward: influencer / partner earn `reward.amountMinor` (per_install), general / campaign have `reward: null` and earn 0 |
| `deferred_custom_deny__<type>` | link type's link | as `deferred_custom_deny`, plus backend `linkType` and nothing earned |
| `deferred_custom_allow_problistic` / `deferred_subdomain_allow_problistic` | `*_problistic_link` | real click, NO token staged, allow: the install goes out and the app gets its attribution answer. The backend device lookup is not checkable: the plugin exposes no SDK device id |
| `deferred_custom_deny_problistic` / `deferred_subdomain_deny_problistic` | `*_problistic_link` | real click, no token, deny: nothing sent. Backend: the click has 0 installs |
| `reengagement_subdomain_allow` | `subdomain_link` | allow, then the link opens the app: `onLink` once, `source: reengagement`, path + voucher |
| `reengagement_subdomain_deny` | `subdomain_link` | deny, then the link still routes (route-only) |
| `reengagement_type_allow__<type>` | link type's link | installed through the link (as `deferred_custom_allow__<type>`), restarted, the link opens the app: `source: reengagement`. Backend against the install: `openCount` +1, `installCount` and earning unchanged (no second reward) |
| `reengagement_type_deny__<type>` | link type's link | the same with deny: `openCount`, `installCount` and earning unchanged |
| `reward_event_allow` / `_deny` | `reward_links.per_event` | counted install, then `reward.eventName` twice + one other event from the E2E panel: earning `2 × reward.amountMinor`, the click's events match. Deny: the SDK drops them, earning 0, events 0. Skipped on prod (no `e2e-event` link yet) |
| `reward_revshare_allow` / `_deny` | `reward_links.rev_share` | counted install, then one revenue event in the reward currency + one in another currency: earning `floor(1999 × rateBps / 10000)`, the click's revenue matches. Deny: nothing |
| `track_event` | none | allow, then `trackEvent("e2e_purchase", value: 9.99, currency: "USD")` succeeds |

`<type>` is each of `general`, `campaign`, `influencer`, `partner` (`E2E_LINK_TYPES`).

How the click is staged:

- **Android:** the script makes a real click with an Android Chrome user agent, takes `lt_click`
  from the Play Store redirect and stages it with the native SDK's debug fake referrer
  (`adb shell setprop debug.linktrail.referrer "lt_click=<token>"`). Probabilistic rows stage nothing.
  The Play Store install-referrer flow of the native Android suite is not ported (it needs a real
  Play install and stays in the private Android SDK repo).
- **iOS:** `e2e/flows/ios/safari_click.yaml` opens the link in Safari, the interstitial puts the
  token on the clipboard, and the deferred flow taps the native Paste button. Probabilistic rows clear
  the clipboard and answer with Continue, so no token is read.

The app is launched at least `MIN_CTIT_WAIT` (15 s) after its click: the backend flags a faster
install as click injection. On iOS a link opens the installed app through `LinkTrail.handleDeepLink`
from the E2E panel, because an unsigned simulator build has no associated domains. On Android it is a
real https App Link (the script approves the link hosts for the app).

The example's deny path (Deny + Continue) only records the choice, because it defers the install
(`autoTrackInstall: false`): a deny row sends nothing and delivers no deferred link. The native suites
deny tracking but still route the deferred link; that wiring is the example app's, not the plugin's.

### Run locally

```sh
# Android: a booted emulator or device
bash e2e/run.sh android                              # every row
bash e2e/run.sh android consent_deny                 # one row
bash e2e/run.sh android deferred_custom_allow        # a flow and its link-type rows
bash e2e/run.sh android deferred_custom_allow__partner

# iOS: a booted simulator (or DEVICE=<udid>)
bash e2e/run.sh ios

# Plan only (no device): what would run, and what is skipped and why
python3 e2e/e2e-env.py plan
LINKTRAIL_ENV=dev python3 e2e/e2e-env.py plan

# The config and rules on their own
python3 -m unittest discover -s e2e/tests
```

Without `LINKTRAIL_KEY` only the consent rows run. To run the real rows, export `LINKTRAIL_KEY` (and
`E2E_TOKEN` for the backend checks) in your shell. The script passes the key to the build through a
private temp file and never prints either secret. The real rows make real clicks and installs on the
e2e workspace's links, so run them sparingly.

Choices (env vars locally; workflow inputs or repository variables in CI): `LINKTRAIL_ENV`
(`prod` | `dev`, `test` = `dev`), `E2E_CUSTOM_LINK`, `E2E_SUBDOMAIN_LINK`,
`E2E_CUSTOM_PROBLISTIC_LINK`, `E2E_SUBDOMAIN_PROBLISTIC_LINK` (a full URL on the environment's host,
or a bare slug), `E2E_LINK_TYPES` (`all` | `none` | a comma list), `E2E_EXPECT_VOUCHER`. A `dev` run
points the app at the dev backend: Android through `debug.linktrail.base`, iOS through
`LINKTRAIL_BASE` in the simulator's launchd environment (read by the DEBUG native SDK).

### CI

`.github/workflows/e2e.yml` runs on every pull request and on manual dispatch (inputs: environment,
link types, custom and subdomain link overrides). All jobs run on GitHub-hosted runners:

- **E2E config:** the unit tests in `e2e/tests`, a plan for every environment and the scripts'
  syntax. No secrets.
- **Native SDK versions:** `scripts/check-native-versions.py` compares the pinned `LinkTrailSDK`
  (podspec and Package.swift) and `io.linktrail:sdk` with the latest on CocoaPods trunk and Maven
  Central and fails on an outdated pin (set the repository variable
  `NATIVE_VERSION_CHECK_STRICT=false` to only warn).
- **Android:** an API 35 emulator on `ubuntu-latest` with KVM.
- **iOS:** a simulator on `macos-latest`, same-repo pull requests and manual runs only.

Each platform writes its row table to the job summary and uploads `build/e2e/` as an artifact.

Repository secrets: `LINKTRAIL_KEY` (prod e2e workspace), `LINKTRAIL_TEST_KEY` (dev runs only) and
`E2E_TOKEN`. When they are missing (for example on a fork pull request) the real rows are skipped
with a notice.

The backend checks need the app ids in the backend's `E2E_APP_IDENTIFIERS`: `io.linktrail.demo.store`
(Android) and `io.linktrail.kickflipdemo` (iOS), and the e2e workspace's links attached to both apps.
