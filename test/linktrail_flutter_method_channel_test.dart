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

  test('trackEvent decodes the returned map', () async {
    final result = await platform.trackEvent(name: 'test_event');

    expect(result.id, 1);
    expect(result.attributed, isTrue);
  });
}
