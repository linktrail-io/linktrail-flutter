# KickFlip — LinkTrail Flutter demo

A small Flutter storefront that shows how the **LinkTrail** SDK's deferred deep linking drives
where a user lands after installing. It's the same **KickFlip** demo shipped with the native
[Android](https://github.com/linktrail-io/android-sdk/tree/main/example) and
[iOS](https://github.com/linktrail-io/ios-sdk/tree/main/example) SDKs, rebuilt in Flutter — it
consumes the [`linktrail_flutter`](../) plugin exactly the way your app would (a `path:` dependency
on the parent package).

## Run it

### 1. Add your API key

Supply your workspace SDK key (`lt_live_…`, from the LinkTrail dashboard) at build time, so it
never lands in source control:

```bash
cd example
flutter run --dart-define=LINKTRAIL_API_KEY=lt_live_…
```

Without a key the backend rejects the network call and the app surfaces that on screen via
`LinkTrail.onError` (`LinkTrailInvalidApiKeyException`) — a quick way to confirm the Dart → native →
network → Dart round-trip works. The four deep-link scenarios below fire local `LinkTrailDeepLink`
objects, so the UI is still explorable without a key.

### 2. Build and run

Run on a connected device or emulator (release build installs a launchable app):

```bash
flutter run --release --dart-define=LINKTRAIL_API_KEY=lt_live_… -d <device-id>
```

## The app

Two screens, nothing more:

- **Home** — a category bar on top (All · Basketball · Running · Lifestyle · Skate) and a grid of products.
- **Product** — one product. If a voucher was delivered in the deep link, it shows the voucher badge, the discounted price, and how much you saved.

## The four deferred deep-link scenarios

Tap the **🔗 link button** (app bar) to open the sheet and fire any of these. Each is a real
`LinkTrailDeepLink` — the same object your `onLink` handler receives from a real install.

| Scenario | Deep link | Where you land |
|---|---|---|
| 1 · Just the store | `deepLinkPath: "/"` | Home |
| 2 · Category selected | `deepLinkPath: "/category/running"` | Home with **Running** pre-selected |
| 3 · A product | `deepLinkPath: "/products/aj1"` | The Air Jordan 1 product page |
| 4 · Product + voucher | `deepLinkPath: "/products/aj1"`, `customData: {voucher: "SUMMER25", discountPercent: "25"}` | Product page with **SUMMER25 −25%** applied |

The sheet fabricates the deferred link locally so you don't need a real click → install round-trip.
In production these arrive from the SDK — no code changes in the app.

## How it maps to the SDK

The entire integration is one method — [`Store.route`](lib/store.dart) — which reads `link.path`
and `link.customData` and decides the screen. It's wired up once:

```dart
LinkTrail.onLink.listen((event) {
    store.route(event.link.path, event.link.customData);   // deferred (first launch) AND re-engagement
});
```

| SDK touchpoint | Where |
|---|---|
| `LinkTrail.configure(apiKey:)` + `onLink` / `onAttribution` / `onError` subscriptions | [`lib/main.dart`](lib/main.dart) |
| `route()` — the single method the SDK integration reduces to | [`lib/store.dart`](lib/store.dart) |
| The four demo `LinkTrailDeepLink`s | [`lib/scenarios.dart`](lib/scenarios.dart) |

## Test from the terminal

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
