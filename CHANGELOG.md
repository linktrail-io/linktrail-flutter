## 0.1.0

- Bumped the wrapped native SDKs: iOS `LinkTrailSDK ~> 0.0.10`, Android `io.linktrail:sdk:0.0.4`.
- **Consent gating (GDPR / ePrivacy):** new `LinkTrailOptions.requireConsent` (deny-by-default) and
  `LinkTrail.setConsent(bool)`. The SDK holds the install and drops events until consent is granted;
  deep links still route. No consent getter — replay it from your own storage each launch.
- **Deferred attribution (iOS):** new `LinkTrailOptions.clickTokenSource`
  (`pasteButton` / `automatic`), `LinkTrail.trackInstallWithClickToken(token)`, and a
  `LinkTrailPasteButton` widget hosting Apple's `UIPasteControl` (iOS 16+; renders nothing on
  Android).
- Documented `linkDomains` re-engagement host gating and the cold-start "wire `onLink` before
  `await`" rule.
- Example: full first-launch consent flow (Allow / Deny / Skip + paste button), persisted with
  `shared_preferences` and replayed after `configure`.

## 0.0.2

- Relicensed under MIT.
- Docs: install via the pub.dev package name (`flutter pub add linktrail_flutter`); the git
  dependency is now just a pre-publish fallback.

## 0.0.1

Initial release — a Flutter plugin wrapping the native LinkTrail Android and iOS SDKs for mobile
attribution and deferred deep linking.

- One Dart API (`LinkTrail`) across Android and iOS, wrapping `io.linktrail:sdk` (Maven Central) and
  `LinkTrailSDK` (CocoaPods).
- `configure`, plus `onLink` / `onAttribution` / `onError` broadcast streams (backed by platform
  `EventChannel`s).
- `handleDeepLink`, `trackInstall`, `trackEvent`, `lastAttribution`, `lastDeepLink`, and iOS-only
  App Tracking Transparency / SKAdNetwork helpers.
- Automatic deep-link capture — App Links, Universal Links, and custom schemes — with no
  `MainActivity` / `AppDelegate` boilerplate, on both cold start and while running.
- iOS 13+ UIScene lifecycle support (works on iOS 26 `FlutterSceneDelegate`).
- Typed `LinkTrailException` errors.
- Platforms: Android (min SDK 26), iOS 15+.
