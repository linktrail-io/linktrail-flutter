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
