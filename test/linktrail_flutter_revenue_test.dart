import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';
import 'package:linktrail_flutter/linktrail_flutter_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelLinktrailFlutter();
  const channel = MethodChannel('linktrail_flutter');
  final originalPlatform = LinktrailFlutterPlatform.instance;
  late List<MethodCall> calls;
  Object? Function(MethodCall)? handler;

  setUp(() {
    calls = [];
    handler = (_) => {'id': 7, 'attributed': true, 'duplicate': false};
    LinktrailFlutterPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler!(call);
    });
  });

  tearDown(() {
    LinktrailFlutterPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('trackRevenue', () {
    test('sends normalised arguments and decodes the result', () async {
      final result = await LinkTrail.trackRevenue(
        transactionId: '  1000000123  ',
        value: 9.99,
        currency: 'usd',
        productId: ' pro_monthly ',
      );

      expect(calls.single.method, 'trackRevenue');
      expect(calls.single.arguments, {
        'transactionId': '1000000123',
        'value': 9.99,
        'currency': 'USD',
        'productId': 'pro_monthly',
      });
      expect(result.id, 7);
      expect(result.attributed, isTrue);
      expect(result.duplicate, isFalse);
    });

    test('omits a blank productId and accepts a zero value', () async {
      await LinkTrail.trackRevenue(transactionId: 'a', value: 0, currency: 'EUR', productId: '  ');

      expect(calls.single.arguments['productId'], isNull);
      expect(calls.single.arguments['value'], 0);
    });

    test('accepts a 255 character id', () async {
      await LinkTrail.trackRevenue(transactionId: 'x' * 255, value: 1, currency: 'USD');

      expect(calls, hasLength(1));
    });

    test('decodes a duplicate result without an id', () async {
      handler = (_) => {'id': null, 'attributed': false, 'duplicate': true};

      final result = await LinkTrail.trackRevenue(transactionId: 'a', value: 1, currency: 'USD');

      expect(result.id, isNull);
      expect(result.duplicate, isTrue);
    });

    test('defaults duplicate to false when the native side omits it', () async {
      handler = (_) => {'id': 1, 'attributed': true};

      final result = await LinkTrail.trackRevenue(transactionId: 'a', value: 1, currency: 'USD');

      expect(result.duplicate, isFalse);
    });

    final invalid = <String, ({String id, double value, String currency})>{
      'empty id': (id: '', value: 1, currency: 'USD'),
      'blank id': (id: '   ', value: 1, currency: 'USD'),
      'id over 255 chars': (id: 'x' * 256, value: 1, currency: 'USD'),
      'negative value': (id: 'a', value: -0.01, currency: 'USD'),
      'NaN value': (id: 'a', value: double.nan, currency: 'USD'),
      'infinite value': (id: 'a', value: double.infinity, currency: 'USD'),
      'short currency': (id: 'a', value: 1, currency: 'US'),
      'long currency': (id: 'a', value: 1, currency: 'USDX'),
      'non-letter currency': (id: 'a', value: 1, currency: 'U\$D'),
    };
    invalid.forEach((name, args) {
      test('rejects $name without calling native', () async {
        await expectLater(
          LinkTrail.trackRevenue(transactionId: args.id, value: args.value, currency: args.currency),
          throwsA(isA<LinkTrailInvalidRevenueException>()),
        );
        expect(calls, isEmpty);
      });
    });

    test('maps a native invalidRevenue PlatformException to a typed exception', () async {
      handler = (_) => throw PlatformException(code: 'invalidRevenue', message: 'bad input');

      await expectLater(
        platform.trackRevenue(transactionId: 'a', value: 1, currency: 'USD'),
        throwsA(isA<LinkTrailInvalidRevenueException>().having((e) => e.message, 'message', 'bad input')),
      );
    });

    test('maps other native errors through the shared mapping', () async {
      handler = (_) => throw PlatformException(code: 'invalidApiKey');

      await expectLater(
        LinkTrail.trackRevenue(transactionId: 'a', value: 1, currency: 'USD'),
        throwsA(isA<LinkTrailInvalidApiKeyException>()),
      );
    });
  });
}
