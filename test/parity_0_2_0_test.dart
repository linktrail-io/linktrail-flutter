import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('linktrail_flutter');
  const onErrorChannel = EventChannel('linktrail_flutter/onError');

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(onErrorChannel, null);
  });

  group('invalidEvent', () {
    test('maps to LinkTrailInvalidEventException with the native reason and message', () {
      final e = LinkTrailException.fromPlatformException(
        PlatformException(
          code: 'invalidEvent',
          message: 'Invalid event: name is blank',
          details: {'reason': 'name is blank'},
        ),
      );
      expect(e, isA<LinkTrailInvalidEventException>());
      expect(e.code, 'invalidEvent');
      expect(e.message, 'Invalid event: name is blank');
      expect((e as LinkTrailInvalidEventException).reason, 'name is blank');
    });

    test('does not fall through to LinkTrailUnknownException without details', () {
      final e = LinkTrailException.fromPlatformException(PlatformException(code: 'invalidEvent', message: 'm'));
      expect(e, isA<LinkTrailInvalidEventException>());
      expect((e as LinkTrailInvalidEventException).reason, '');
    });

    test('is thrown from trackEvent, which forwards the arguments without checking them', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        throw PlatformException(
          code: 'invalidEvent',
          message: 'Invalid event: value must not be negative (got -1.0)',
          details: {'reason': 'value must not be negative (got -1.0)'},
        );
      });
      await expectLater(
        MethodChannelLinktrailFlutter().trackEvent(name: 'purchase', value: -1, currency: 'usd'),
        throwsA(
          isA<LinkTrailInvalidEventException>()
              .having((e) => e.reason, 'reason', 'value must not be negative (got -1.0)')
              .having((e) => e.message, 'message', 'Invalid event: value must not be negative (got -1.0)'),
        ),
      );
      expect(seen!.method, 'trackEvent');
      expect(seen!.arguments['value'], -1);
      expect(seen!.arguments['currency'], 'usd');
    });

    test('arrives on onError with the reason', () async {
      messenger.setMockStreamHandler(
        onErrorChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) => sink.success({
            'code': 'invalidEvent',
            'message': 'Invalid event: currency must be a 3-letter ISO 4217 code (got "US")',
            'details': {'reason': 'currency must be a 3-letter ISO 4217 code (got "US")'},
          }),
        ),
      );
      final error = await MethodChannelLinktrailFlutter().onError.first;
      expect(error, isA<LinkTrailInvalidEventException>());
      expect((error as LinkTrailInvalidEventException).reason, 'currency must be a 3-letter ISO 4217 code (got "US")');
    });
  });
}
