import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';
import 'package:linktrail_flutter/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelLinktrailFlutter();
  const channel = MethodChannel('linktrail_flutter');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      calls.add(methodCall);
      switch (methodCall.method) {
        case 'configure':
          return null;
        case 'trackEvent':
          return {'id': 1, 'attributed': true};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('configure sends the api key and encoded options', () async {
    await platform.configure(apiKey: 'lt_live_test', options: const LinkTrailOptions());

    expect(calls.single.method, 'configure');
    expect(calls.single.arguments['apiKey'], 'lt_live_test');
    expect(calls.single.arguments['options'], isA<Map>());
  });

  test('updatePostbackConversionValue sends the typed arguments and returns the native result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final ok = await platform.updatePostbackConversionValue(
      12,
      coarseValue: LinkTrailCoarseConversionValue.high,
      lockPostback: true,
      conversionTypes: {LinkTrailConversionType.reengagement, LinkTrailConversionType.install},
    );

    expect(ok, isTrue);
    expect(calls.single.method, 'updatePostbackConversionValue');
    expect(calls.single.arguments, {
      'value': 12,
      'coarseValue': 'high',
      'lockPostback': true,
      'conversionTypes': ['install', 'reengagement'],
    });
  });

  test('updatePostbackConversionValue defaults to all types, unlocked, and treats null as false', () async {
    final ok = await platform.updatePostbackConversionValue(3);

    expect(ok, isFalse);
    expect(calls.single.arguments, {
      'value': 3,
      'coarseValue': null,
      'lockPostback': false,
      'conversionTypes': <String>[],
    });
  });

  test('trackEvent decodes the returned map', () async {
    final result = await platform.trackEvent(name: 'test_event');

    expect(result.id, 1);
    expect(result.attributed, isTrue);
  });
}
