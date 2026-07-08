import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';
import 'package:linktrail_flutter/linktrail_flutter_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockLinktrailFlutterPlatform with MockPlatformInterfaceMixin implements LinktrailFlutterPlatform {
  String? configuredApiKey;

  @override
  Future<void> configure({required String apiKey, required LinkTrailOptions options}) async {
    configuredApiKey = apiKey;
  }

  @override
  Future<LinkTrailEventResult> trackEvent({required String name, double? value, String? currency}) {
    return Future.value(const LinkTrailEventResult(id: 1, attributed: true));
  }

  @override
  Stream<LinkTrailLinkEvent> get onLink => const Stream.empty();

  @override
  Stream<LinkTrailAttribution> get onAttribution => const Stream.empty();

  @override
  Stream<LinkTrailException> get onError => const Stream.empty();

  @override
  Future<bool> handleDeepLink(Uri url) => Future.value(true);

  @override
  Future<LinkTrailAttribution> trackInstall({required bool force}) {
    return Future.value(const LinkTrailAttribution(attributed: true));
  }

  @override
  Future<LinkTrailAttribution?> getLastAttribution() => Future.value(null);

  @override
  Future<LinkTrailDeepLink?> getLastDeepLink() => Future.value(null);

  @override
  Future<bool> requestTrackingAuthorization() => Future.value(true);

  @override
  Future<void> registerForSKAdAttribution() => Future.value();

  @override
  Future<void> updateConversionValue(int value, {LinkTrailCoarseConversionValue? coarseValue}) => Future.value();

  @override
  Future<void> resetForTesting() => Future.value();
}

void main() {
  final LinktrailFlutterPlatform initialPlatform = LinktrailFlutterPlatform.instance;

  test('$MethodChannelLinktrailFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelLinktrailFlutter>());
  });

  test('configure forwards to the platform implementation', () async {
    final fakePlatform = MockLinktrailFlutterPlatform();
    LinktrailFlutterPlatform.instance = fakePlatform;

    await LinkTrail.configure(apiKey: 'lt_live_test');

    expect(fakePlatform.configuredApiKey, 'lt_live_test');
  });

  test('trackEvent forwards the result through', () async {
    LinktrailFlutterPlatform.instance = MockLinktrailFlutterPlatform();

    final result = await LinkTrail.trackEvent(name: 'test_event');

    expect(result.attributed, isTrue);
  });
}
