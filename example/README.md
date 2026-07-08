# KickFlip — LinkTrail Flutter example

A small Flutter storefront that shows **deferred deep linking** end to end with the
[`linktrail_flutter`](../) plugin. It's the same **KickFlip** demo shipped with the native
[Android](https://github.com/linktrail-io/android-sdk/tree/main/example) and
[iOS](https://github.com/linktrail-io/ios-sdk/tree/main/example) SDKs, rebuilt in Flutter — it
consumes the plugin exactly the way your app would (a `path:` dependency on the parent package).

The whole integration collapses into one method — [`Store.route`](lib/store.dart) — wired once to
`LinkTrail.onLink`. The link button in the app bar fires the same `LinkTrailDeepLink` objects into
it, so you can see each scenario without a real click → install round-trip.

## Run

Supply your `lt_live_…` key from the LinkTrail dashboard at build time (it is never hardcoded):

```bash
flutter run --dart-define=LINKTRAIL_API_KEY=lt_live_…
```

Without a key the backend rejects the request, and the app surfaces that on screen via
`LinkTrail.onError` (`LinkTrailInvalidApiKeyException`) — a quick way to confirm the Dart → native →
network → Dart round-trip works on both platforms.

To run standalone on a device (installs a build you can launch from the home screen):

```bash
flutter run --release --dart-define=LINKTRAIL_API_KEY=lt_live_… -d <device-id>
```

## The four scenarios

The link button (🔗) opens a sheet that fires the four deferred-deep-link scenarios from the brief:

| Scenario | `deepLinkPath` | Result |
|---|---|---|
| Just the store | `/` | Home |
| Category selected | `/category/running` | Home, Running pre-selected |
| A product | `/products/aj1` | Air Jordan 1 |
| Product + voucher | `/products/aj1` + `customData {voucher: SUMMER25, discountPercent: 25}` | Air Jordan 1 with the voucher applied |

## Test a real link from the terminal

With the app installed, fire the registered custom scheme to route while it's running (warm) or
launch it from killed (cold — the plugin buffers and replays the link after `configure`):

```bash
# Android
adb shell am start -a android.intent.action.VIEW \
  -d "kickflip://products/aj1?voucher=SUMMER25&discountPercent=25"

# iOS simulator
xcrun simctl openurl booted "kickflip://products/aj1?voucher=SUMMER25&discountPercent=25"
```

For real attribution and re-engagement links (`https://kick.linktrail.io/…`), set up App Links /
Universal Links per the [plugin README](../README.md#deep-link-setup).

## What to look at

- [`lib/main.dart`](lib/main.dart) — SDK wiring: `configure`, and the `onLink` / `onAttribution` /
  `onError` stream subscriptions.
- [`lib/store.dart`](lib/store.dart) — `route()`, the single method the SDK integration reduces to.
- [`lib/scenarios.dart`](lib/scenarios.dart) — the four demo `LinkTrailDeepLink`s.
