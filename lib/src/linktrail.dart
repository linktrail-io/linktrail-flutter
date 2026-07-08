import '../linktrail_flutter_platform_interface.dart';
import 'errors.dart';
import 'models.dart';

/// Dart facade over the native LinkTrail Android/iOS SDKs — mobile
/// attribution and deferred deep linking.
///
/// Mirrors the native SDKs' singleton shape (`LinkTrail.configure` /
/// `LinkTrail.shared`) as a set of static members, since there is only ever
/// one instance per app.
abstract final class LinkTrail {
  /// Configures the SDK. Must be called once, as early as possible (e.g. in
  /// `main()`), before any other member is used. Unless
  /// [LinkTrailOptions.autoTrackInstall] is set to false, this also tracks
  /// the install/open automatically.
  static Future<void> configure({required String apiKey, LinkTrailOptions options = const LinkTrailOptions()}) {
    return LinktrailFlutterPlatform.instance.configure(apiKey: apiKey, options: options);
  }

  /// Fires for every deep link the SDK delivers — both deferred (first
  /// launch) and re-engagement links. Incoming platform links are captured
  /// automatically; you don't need to forward `Intent`/`URL` values yourself.
  static Stream<LinkTrailLinkEvent> get onLink => LinktrailFlutterPlatform.instance.onLink;

  /// Fires whenever an install/open attribution result is delivered.
  static Stream<LinkTrailAttribution> get onAttribution => LinktrailFlutterPlatform.instance.onAttribution;

  /// Fires on any native SDK failure (network, decoding, a rejected API key, etc).
  static Stream<LinkTrailException> get onError => LinktrailFlutterPlatform.instance.onError;

  /// Resolves an incoming link directly, in addition to the automatic
  /// capture — useful for testing or for links your app already had to parse
  /// for other reasons. Returns whether the SDK recognized and handled it.
  static Future<bool> handleDeepLink(Uri url) {
    return LinktrailFlutterPlatform.instance.handleDeepLink(url);
  }

  /// Tracks an install/open event. Called automatically by [configure]
  /// unless [LinkTrailOptions.autoTrackInstall] is false; [force] re-sends
  /// it regardless of whether it was already tracked this session.
  static Future<LinkTrailAttribution> trackInstall({bool force = false}) {
    return LinktrailFlutterPlatform.instance.trackInstall(force: force);
  }

  /// Tracks a custom event, optionally with a monetary [value] in [currency]
  /// (ISO 4217, e.g. `"USD"`).
  static Future<LinkTrailEventResult> trackEvent({required String name, double? value, String? currency}) {
    return LinktrailFlutterPlatform.instance.trackEvent(name: name, value: value, currency: currency);
  }

  /// The most recent attribution result, if any, without re-fetching.
  static Future<LinkTrailAttribution?> get lastAttribution => LinktrailFlutterPlatform.instance.getLastAttribution();

  /// The most recent delivered deep link, if any, without re-fetching.
  static Future<LinkTrailDeepLink?> get lastDeepLink => LinktrailFlutterPlatform.instance.getLastDeepLink();

  /// Requests App Tracking Transparency authorization. iOS-only; resolves to
  /// `true` immediately on Android.
  static Future<bool> requestTrackingAuthorization() {
    return LinktrailFlutterPlatform.instance.requestTrackingAuthorization();
  }

  /// Registers for SKAdNetwork attribution. iOS-only; no-op on Android.
  static Future<void> registerForSKAdAttribution() {
    return LinktrailFlutterPlatform.instance.registerForSKAdAttribution();
  }

  /// Updates the SKAdNetwork conversion value. iOS-only; no-op on Android.
  static Future<void> updateConversionValue(int value, {LinkTrailCoarseConversionValue? coarseValue}) {
    return LinktrailFlutterPlatform.instance.updateConversionValue(value, coarseValue: coarseValue);
  }

  /// Clears all persisted SDK state. Test-only.
  static Future<void> resetForTesting() {
    return LinktrailFlutterPlatform.instance.resetForTesting();
  }
}
