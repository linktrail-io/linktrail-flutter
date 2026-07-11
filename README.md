# LinkTrail Flutter SDK

Mobile **attribution** and **deferred deep linking** for Flutter. A thin plugin over the native
LinkTrail SDKs — package `linktrail_flutter`, entry point `LinkTrail`. Wraps the
[LinkTrail Android](https://github.com/linktrail-io/android-sdk) and
[iOS](https://github.com/linktrail-io/ios-sdk) SDKs, exposing one Dart API across both platforms.

- **Package:** `linktrail_flutter` · **Android:** minSdk 26 · **iOS:** 15+
- **Native SDKs wrapped:** `io.linktrail:sdk` (Maven Central) · `LinkTrailSDK` (CocoaPods)

## Install

Add the dependency to your app's `pubspec.yaml` (a pub.dev release is coming; until then, install
straight from GitHub):

```yaml
dependencies:
  linktrail_flutter:
    git:
      url: https://github.com/linktrail-io/linktrail-flutter.git
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
await LinkTrail.handleDeepLink(uri);                       // resolve a link manually (also auto-captured)
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

Errors from the native SDKs arrive as typed `LinkTrailException` subtypes on `onError`, and are
thrown from the `Future`-returning calls — so you can `try/catch` a specific case:

```dart
try {
  await LinkTrail.trackEvent(name: 'purchase');
} on LinkTrailInvalidApiKeyException {
  // the key was rejected by the server
}
```

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

Then host a Digital Asset Links file at `https://<host>/.well-known/assetlinks.json` listing your
package + signing-cert SHA-256 (LinkTrail infra hosts this for your links). If links open the
browser or Play Store instead of your installed app, that's almost always App Links verification —
see the Android SDK's [TROUBLESHOOTING.md](https://github.com/linktrail-io/android-sdk/blob/main/TROUBLESHOOTING.md).

### iOS

Add the **Associated Domains** capability with `applinks:kick.linktrail.io`, and host an
`apple-app-site-association` file on that domain. For a custom scheme, add it under
`CFBundleURLTypes` in `ios/Runner/Info.plist`:

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

## Example app

[`example/`](example/) is **KickFlip**, a small storefront that demonstrates deferred deep linking
end to end — the same demo shipped with the native Android and iOS SDKs, rebuilt in Flutter. A link
button fires the four scenarios (home · category · product · product + voucher):

```bash
cd example && flutter run --dart-define=LINKTRAIL_API_KEY=lt_live_…
```

Supply your key at build time so it never lands in source control. See
[example/README.md](example/README.md).

## License

See [LICENSE](LICENSE).
