import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'linktrail_flutter_method_channel.dart';
import 'src/errors.dart';
import 'src/models.dart';

abstract class LinktrailFlutterPlatform extends PlatformInterface {
  /// Constructs a LinktrailFlutterPlatform.
  LinktrailFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static LinktrailFlutterPlatform _instance = MethodChannelLinktrailFlutter();

  /// The default instance of [LinktrailFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelLinktrailFlutter].
  static LinktrailFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LinktrailFlutterPlatform] when
  /// they register themselves.
  static set instance(LinktrailFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> configure({required String apiKey, required LinkTrailOptions options}) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Stream<LinkTrailLinkEvent> get onLink {
    throw UnimplementedError('onLink has not been implemented.');
  }

  Stream<LinkTrailAttribution> get onAttribution {
    throw UnimplementedError('onAttribution has not been implemented.');
  }

  Stream<LinkTrailException> get onError {
    throw UnimplementedError('onError has not been implemented.');
  }

  Future<bool> handleDeepLink(Uri url) {
    throw UnimplementedError('handleDeepLink() has not been implemented.');
  }

  Future<LinkTrailAttribution> trackInstall({required bool force}) {
    throw UnimplementedError('trackInstall() has not been implemented.');
  }

  Future<LinkTrailEventResult> trackEvent({required String name, double? value, String? currency}) {
    throw UnimplementedError('trackEvent() has not been implemented.');
  }

  Future<LinkTrailAttribution?> getLastAttribution() {
    throw UnimplementedError('getLastAttribution() has not been implemented.');
  }

  Future<LinkTrailDeepLink?> getLastDeepLink() {
    throw UnimplementedError('getLastDeepLink() has not been implemented.');
  }

  Future<bool> requestTrackingAuthorization() {
    throw UnimplementedError('requestTrackingAuthorization() has not been implemented.');
  }

  Future<void> registerForSKAdAttribution() {
    throw UnimplementedError('registerForSKAdAttribution() has not been implemented.');
  }

  Future<void> updateConversionValue(int value, {LinkTrailCoarseConversionValue? coarseValue}) {
    throw UnimplementedError('updateConversionValue() has not been implemented.');
  }

  Future<void> resetForTesting() {
    throw UnimplementedError('resetForTesting() has not been implemented.');
  }
}
