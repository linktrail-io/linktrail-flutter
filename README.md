# LinkTrail Flutter SDK

Mobile **attribution** and **deferred deep linking** for Flutter. A thin plugin over the native
LinkTrail SDKs — package `linktrail_flutter`, entry point `LinkTrail`. Wraps the
[LinkTrail Android](https://github.com/linktrail-io/android-sdk) and
[iOS](https://github.com/linktrail-io/ios-sdk) SDKs, exposing one Dart API across both platforms.

- **Package:** [`linktrail_flutter`](https://pub.dev/packages/linktrail_flutter) (pub.dev) · **Android:** minSdk 26 · **iOS:** 15+
- **Native SDKs wrapped:** `io.linktrail:sdk` (Maven Central) · `LinkTrailSDK` (CocoaPods)

## Install

```bash
flutter pub add linktrail_flutter
```

or add it to your app's `pubspec.yaml`:

```yaml
dependencies:
  linktrail_flutter: ^0.1.1
```

Then `flutter pub get`. The native SDKs are pulled in automatically — no manual Gradle or CocoaPods
edits needed. On iOS run `pod install` in `ios/` (or let `flutter run` do it).

Platform minimums the SDK requires — set them if your app targets lower:

```kotlin
// android/app/build.gradle.kts
android { defaultConfig { minSdk = 26 } }
```

```ruby
# ios/Podfile
platform :ios, '15.0'
```

## Quick start

```dart
import 'package:linktrail_flutter/linktrail_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One hook handles both first-launch (deferred) AND re-engagement links.
  LinkTrail.onLink.listen((event) {
    router.route(event.link.path, event.link.customData); // e.g. "/products/aj1" + {voucher: SUMMER25}
  });

  // Observe failures if you want (e.g. LinkTrailInvalidApiKeyException).
  LinkTrail.onError.listen((error) => debugPrint('LinkTrail: $error'));

  // The API key is required. The install is tracked automatically by configure().
  await LinkTrail.configure(apiKey: 'lt_live_…');

  runApp(const MyApp());
}
```

Incoming links are **captured automatically** — you do **not** need to override `MainActivity`
(Android) or `AppDelegate`/`SceneDelegate` (iOS). The plugin forwards App Links, Universal Links and
custom-scheme opens to the SDK for you, on both cold start and while running. Every callback is a
broadcast `Stream`, so you can listen from multiple places (e.g. a `StreamBuilder`).

## More

```dart
// Configuration
await LinkTrail.configure(apiKey: 'lt_live_…', options: LinkTrailOptions(...));

// Streams (native callbacks, surfaced as Dart streams)
LinkTrail.onLink;         // Stream<LinkTrailLinkEvent>   — (link, source: deferred | reengagement)
LinkTrail.onAttribution;  // Stream<LinkTrailAttribution>
LinkTrail.onError;        // Stream<LinkTrailException>

// Actions
await LinkTrail.handleDeepLink(uri);                       // resolve a link manually (also auto-captured) -> bool
await LinkTrail.resolveDeepLink(uri);                      // same, returns LinkTrailDeepLink? (null = not a LinkTrail URL)
await LinkTrail.trackInstall(force: false);                // called automatically by configure()
await LinkTrail.trackEvent(name: 'purchase', value: 9.99, currency: 'USD');

// Last known state
await LinkTrail.lastAttribution;
await LinkTrail.lastDeepLink;

// iOS-only (no-ops on Android)
await LinkTrail.requestTrackingAuthorization();            // App Tracking Transparency
await LinkTrail.registerForSKAdAttribution();
await LinkTrail.updateConversionValue(3, coarseValue: LinkTrailCoarseConversionValue.medium);
```

`onLink` never misses a link delivered before you listen: the native callback is registered when
the first listener subscribes (a deferred link stays saved natively until then), and links that
arrive while nobody listens are held (up to 10, this process only) and delivered once, in order, to
the next listener. `onAttribution` replays the latest result to its first listener.

### Deferred link delivery

When the install resolves a deferred link, the native SDK saves it until `onLink` has a listener
and then delivers it (`source: deferred`) **at least once**, even on a later launch if the app was
killed first. So you can listen after a splash, onboarding or login screen. A saved link older than
**7 days** is dropped and never delivered. The first deferred link wins: while one is waiting, a
later install doesn't replace it. Delivery can repeat, so make your `onLink` handler safe to run
twice for the same link.

### `configure` is a singleton

Calling `configure` again with the same key and options is a no-op. A call with a different key or
different options shuts the previous native instance down (its pending work is cancelled) and
replaces it. Your Dart stream subscriptions stay valid: the plugin re-registers its native
callbacks on every `configure`.

### Testing

`LinkTrail.resetForTesting()` clears the native SDK state (install flag, cached attribution, saved
deferred link, queued events and device id), so the next launch sends a fresh install. Use it in
tests and QA builds only.

Incoming links are captured for you (`LinkTrailOptions.autoHandleLinks`, default `true`): the launch
link (held until `configure` on a cold start) and every later one, on Android (`Intent`) and iOS
(app and scene delegates), go to the native `handleDeepLink`. Set it to `false` to route links
yourself with `handleDeepLink` / `resolveDeepLink`.

Errors from the native SDKs arrive as typed `LinkTrailException` subtypes on `onError`, and are
thrown from the `Future`-returning calls — so you can `try/catch` a specific case:

```dart
try {
  await LinkTrail.trackEvent(name: 'purchase');
} on LinkTrailInvalidApiKeyException {
  // the key was rejected by the server
}
```

## Consent gating (GDPR / ePrivacy)

`LinkTrailOptions.requireConsent` defaults to **`true`** — **deny-by-default**:

| Decision | What the SDK sends |
| --- | --- |
| not made yet | nothing: the install is **held** (persisted across launches) and events are dropped |
| granted (`setConsent(true)`) | the install with `consent: true`, counted and attributed; events are sent |
| denied (`setConsent(false)`) | **one** install with `consent: false` and no device id, so the deep link still resolves and the user is routed, but nothing is recorded; queued and new events are dropped |

Because the deferred link is resolved by that install, it routes **after** the user answers,
whichever answer it is. `setConsent(false)` always wins, even with `requireConsent: false`.

There is **no consent getter** — the app is the source of truth. Persist the choice yourself and
replay it on **every launch** right after `configure`, so a previously-granted user resumes
automatically:

```dart
await LinkTrail.configure(apiKey: 'lt_live_…', options: const LinkTrailOptions(requireConsent: true));

// Replay the persisted decision (e.g. from SharedPreferences). Do nothing while undecided.
final consent = await loadConsent();          // 'granted' | 'denied' | 'undecided'
if (consent == 'granted') await LinkTrail.setConsent(true);
if (consent == 'denied') await LinkTrail.setConsent(false);
```

Set `requireConsent: false` to opt out of gating and track automatically (the pre-consent
behavior). An explicit `setConsent(false)` still wins.

## `linkDomains` — custom link domains

The SDK only claims `https` links on `linktrail.io` (or a subdomain) and on the hosts you list in
`LinkTrailOptions.linkDomains` (or their subdomains). If your links use your own domain, list it:

```dart
await LinkTrail.configure(
  apiKey: 'lt_live_…',
  options: const LinkTrailOptions(linkDomains: ['go.acme.com']),
);
```

Any other URL (`mailto:`, OAuth callbacks, `myapp://settings`) is ignored: `handleDeepLink`
returns `false`, no request is made and `onError` does not fire, so route those yourself.
Custom-scheme LinkTrail links (`myapp://slug`) are not handled; use the `https` link. Links on
`*.linktrail.io` need no entry.

**Upgrading from 0.0.x:** an empty `linkDomains` no longer means "handle every link". If you relied
on that with your own domain, list it:

```dart
// 0.0.x: worked with no linkDomains
await LinkTrail.configure(apiKey: 'lt_live_…');
// 0.1.0+: custom domains must be listed
await LinkTrail.configure(
  apiKey: 'lt_live_…',
  options: const LinkTrailOptions(linkDomains: ['go.acme.com']),
);
```

## `customData` values

`LinkTrailDeepLink.customData` is a `Map<String, String>`. A nested object or array set on the link
arrives as a compact JSON string (`{"x":1}`, `["a","b"]`) on both platforms; decode it with
`jsonDecode` when you need the structure.

## Deferred attribution & the paste button (iOS)

On iOS, deferred attribution recovers a **click token** the tapped link leaves on the clipboard.
`LinkTrailOptions.clickTokenSource` chooses how it's read:

- **`pasteButton`** (default) — the token is read only when the user taps a `LinkTrailPasteButton`
  (Apple's `UIPasteControl`), with **no system "Allow Paste" alert**. Render the button **and** set
  `autoTrackInstall: false` so the install waits for the tap.
- **`automatic`** — the SDK reads the clipboard itself at install (no UI, but iOS shows the "Allow
  Paste" alert on first launch).
- **`none`** — the SDK never touches the clipboard (no button, no alert, and even
  `trackInstallWithClickToken` ignores a token handed to it). Deferred matching falls back to
  probabilistic IP matching only.

```dart
LinkTrailPasteButton(
  // null (default): the tap grants consent only while it is still undecided.
  // true: always grants, even after a denial. false: never touches consent.
  grantsConsent: null,
  onToken: (token) {
    // The SDK has already sent the install with the token; advance your UI here.
  },
)
```

The tap goes through the native SDK's paste button: it records consent per `grantsConsent` and
sends the install with the click token itself, so don't also call `trackInstallWithClickToken` from
`onToken`. With the default `null`, an earlier `setConsent(false)` stands; the pasted token is still
used to route the user (the install goes out with `consent: false`).

The widget renders the native control on iOS 16+ and **nothing on Android** (Play Install Referrer
handles deferred attribution there, so `clickTokenSource` and the paste button are ignored). Apple
restricts customization — no custom label text, font or border.

## Implementation notes

- **You can subscribe to `onLink` late.** A deferred link stays saved natively until the first
  listener subscribes, and re-engagement links that arrive with no listener are held (up to 10, this
  process only). See [Deferred link delivery](#deferred-link-delivery).
- Consent has no getter — replay it from your own storage on every launch (see above).

## Deep-link setup

The plugin captures links automatically, but the OS still needs to route the link to your app.

### Android

Declare your App Links host (and optionally a custom scheme) in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="kick.linktrail.io" />
</intent-filter>
```

LinkTrail hosts the Digital Asset Links file (`https://<host>/.well-known/assetlinks.json`) for
your link domains; register your package name and signing-cert SHA-256 with LinkTrail. If links
open the browser or Play Store instead of your installed app, that's almost always App Links verification —
see the Android SDK's [TROUBLESHOOTING.md](https://github.com/linktrail-io/android-sdk/blob/main/TROUBLESHOOTING.md).

### iOS

Add the **Associated Domains** capability with `applinks:kick.linktrail.io` (one entry per link
host). LinkTrail hosts the `apple-app-site-association` file for your link domains. Custom URL
schemes are your own routing (the SDK only claims `https` LinkTrail links); if your app uses one,
add it under `CFBundleURLTypes` in `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>kickflip</string></array>
  </dict>
</array>
```

On iOS 13+ the plugin registers on the **UIScene lifecycle**, so links are delivered correctly on
iOS 26 (`FlutterSceneDelegate`) as well as the classic app-delegate lifecycle.

Every custom link host you declare here must also be in `linkDomains` (see
[`linkDomains`](#linkdomains--custom-link-domains)).

## Error codes

Every `LinkTrailException` has a camelCase `code` matching the native error case, and its `message`
is the native SDK's message, unchanged: `missingApiKey`, `invalidApiKey`, `notConfigured`,
`invalidUrl`, `notALinkTrailUrl`, `transport`, `server`, `decoding`, `emptyResponse`,
`invalidArgument`. `LinkTrailServerException` also has `statusCode` and `body`.

## Upgrading to 0.1.0

0.1.0 wraps the native 0.1.0 SDKs (iOS `LinkTrailSDK` 0.1.0, Android `io.linktrail:sdk` 0.1.0),
which have breaking changes:

- **Custom link domains must be listed in `linkDomains`; `handleDeepLink` now ignores non-LinkTrail
  URLs.** Only `https` links on `linktrail.io` or a `linkDomains` host are claimed. Custom-scheme
  LinkTrail links (`myapp://slug`) are no longer handled; use the `https` link.
- **`LinkTrailPasteButton` handles the install and consent itself.** New `grantsConsent` (`bool?`,
  default `null` = grant only while undecided). Remove any `trackInstallWithClickToken` call from
  `onToken`. Pass `grantsConsent: true` for the old "the tap always grants" behaviour.
- **Nested `customData` values arrive as JSON strings** (see above).
- **`setConsent(false)` wins even with `requireConsent: false`**, and SDK state is no longer backed
  up, so a restored or migrated device asks for consent again.
- Android requests now send `X-LinkTrail-SDK: flutter/<plugin version>` (iOS still reports
  `ios/<version>` until the native SDK exports its wrapper hook).

See the native changelogs for the full list.

## Example app

[`example/`](example/) is **KickFlip**, a small storefront that demonstrates deferred deep linking
end to end — the same demo shipped with the native Android and iOS SDKs, rebuilt in Flutter. A link
button fires the four scenarios (home · category · product · product + voucher):

```bash
cd example && flutter run --dart-define=LINKTRAIL_API_KEY=lt_live_…
```

Supply your key at build time so it never lands in source control. See
[example/README.md](example/README.md).

## Auto-merge

Put `auto-merge` anywhere in a PR title (any case, e.g. `[auto-merge] Fix typo`) and the
`Auto-merge` workflow (`.github/workflows/auto-merge.yml`) turns on GitHub auto-merge for it.
GitHub then merges it with a merge commit (never squash, so stacked PRs keep working) once the
required checks and approvals pass. Drafts are skipped: auto-merge turns on when the PR is marked
ready for review. Remove the word from the title, or convert the PR back to draft, to turn it off.
PRs from forks are ignored. Until the `AUTOMERGE_TOKEN` org secret exists, the merge is made with
`GITHUB_TOKEN`, which does not trigger the push workflows on the base branch.

This repo's `main` ruleset requires an approving review, so auto-merge completes only after the PR is approved.

## License

MIT — see [LICENSE](LICENSE). Note the plugin is open source, but the LinkTrail service it talks to
requires a workspace API key.

## Releasing

Releases are published to pub.dev automatically when a `vX.Y.Z` tag is pushed. See [RELEASING.md](RELEASING.md).
