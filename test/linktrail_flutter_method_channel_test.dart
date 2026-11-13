import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';

/// Exercises the real [MethodChannelLinktrailFlutter] against a fake native side
/// installed on the binary messenger, so argument encoding, result decoding,
/// error mapping and the event streams go through the real platform codecs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('linktrail_flutter');
  late MethodChannelLinktrailFlutter platform;
  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall call) native = (_) async => null;

  setUp(() {
    platform = MethodChannelLinktrailFlutter();
    calls = [];
    native = (_) async => null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return native(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('argument encoding', () {
    test('configure sends the api key and every option, encoded', () async {
      await platform.configure(
        apiKey: 'lt_test_key',
        options: const LinkTrailOptions(
          logEnabled: true,
          logLevel: LinkTrailLogLevel.debug,
          requestTimeout: Duration(seconds: 7),
          retryPolicy: LinkTrailRetryPolicy.disabled,
          linkDomains: ['go.example.com'],
          autoTrackInstall: false,
          requireConsent: false,
          clickTokenSource: LinkTrailClickTokenSource.none,
        ),
      );

      expect(calls.single.method, 'configure');
      final args = calls.single.arguments as Map;
      expect(args['apiKey'], 'lt_test_key');
      final options = (args['options'] as Map).cast<String, Object?>();
      expect(options['logEnabled'], true);
      expect(options['logLevel'], 'debug');
      expect(options['linkDomains'], ['go.example.com']);
      expect(options['autoTrackInstall'], false);
      expect(options['requireConsent'], false);
      expect(options['clickTokenSource'], 'none');
      expect((options['retryPolicy'] as Map)['maxAttempts'], 1);
    });

    test('handleDeepLink sends the url as a string', () async {
      native = (_) async => true;
      await platform.handleDeepLink(Uri.parse('https://go.example.com/abc?x=1'));
      expect(calls.single.method, 'handleDeepLink');
      expect(calls.single.arguments, {'url': 'https://go.example.com/abc?x=1'});
    });

    test('trackInstall / trackInstallWithClickToken send force and token', () async {
      native = (_) async => {'attributed': false};
      await platform.trackInstall(force: true);
      await platform.trackInstallWithClickToken('tok_1', force: false);
      expect(calls[0].arguments, {'force': true});
      expect(calls[1].method, 'trackInstallWithClickToken');
      expect(calls[1].arguments, {'token': 'tok_1', 'force': false});
    });

    test('trackEvent sends name, value and currency (nulls preserved)', () async {
      native = (_) async => {'id': 3, 'attributed': false};
      await platform.trackEvent(name: 'purchase', value: 9.99, currency: 'USD');
      await platform.trackEvent(name: 'signup');
      expect(calls[0].arguments, {'name': 'purchase', 'value': 9.99, 'currency': 'USD'});
      expect(calls[1].arguments, {'name': 'signup', 'value': null, 'currency': null});
    });

    test('setConsent and updateConversionValue encode their arguments', () async {
      await platform.setConsent(true);
      await platform.updateConversionValue(5, coarseValue: LinkTrailCoarseConversionValue.high);
      await platform.updateConversionValue(2);
      expect(calls[0].arguments, {'granted': true});
      expect(calls[1].arguments, {'value': 5, 'coarseValue': 'high'});
      expect(calls[2].arguments, {'value': 2, 'coarseValue': null});
    });

    test('configure forwards linkDomains and the plugin version', () async {
      await platform.configure(
        apiKey: 'lt_live_test',
        options: const LinkTrailOptions(linkDomains: ['go.acme.com']),
      );
      expect(calls.single.arguments['options']['linkDomains'], ['go.acme.com']);
      expect(calls.single.arguments['sdkVersion'], linkTrailFlutterVersion);
    });
  });

  group('result decoding', () {
    test('trackInstall decodes attribution including a nested deep link', () async {
      native = (_) async => {
        'id': 42,
        'attributed': true,
        'deepLink': {
          'slug': 'abc',
          'deepLinkPath': '/product/1',
          'utm': {'utm_source': 'x'},
          'customData': {'k': 'v'},
        },
      };
      final result = await platform.trackInstall(force: false);
      expect(result.id, 42);
      expect(result.attributed, isTrue);
      expect(result.deepLink?.slug, 'abc');
      expect(result.deepLink?.path, '/product/1');
      expect(result.deepLink?.utm, {'utm_source': 'x'});
      expect(result.deepLink?.customData, {'k': 'v'});
    });

    test('trackEvent decodes the result map', () async {
      native = (_) async => {'id': 1, 'attributed': true};
      final result = await platform.trackEvent(name: 'e');
      expect(result.id, 1);
      expect(result.attributed, isTrue);
    });

    test('getLast* return null when native has nothing, a model otherwise', () async {
      expect(await platform.getLastAttribution(), isNull);
      expect(await platform.getLastDeepLink(), isNull);

      native = (call) async => call.method == 'getLastAttribution'
          ? {'attributed': true}
          : {'slug': 's', 'url': 'https://go.example.com/s'};
      expect((await platform.getLastAttribution())?.attributed, isTrue);
      expect((await platform.getLastDeepLink())?.slug, 's');
    });

    test('handleDeepLink treats a null native result as not handled', () async {
      expect(await platform.handleDeepLink(Uri.parse('https://x.test/a')), isFalse);
    });

    test('requestTrackingAuthorization passes through a bool and defaults null to false', () async {
      native = (_) async => true;
      expect(await platform.requestTrackingAuthorization(), isTrue);
      native = (_) async => false;
      expect(await platform.requestTrackingAuthorization(), isFalse);
      native = (_) async => null;
      expect(await platform.requestTrackingAuthorization(), isFalse);
    });
  });

  group('error mapping', () {
    Future<void> expectMapped(String code, Matcher matcher, {String? message, Object? details}) async {
      native = (_) async => throw PlatformException(code: code, message: message, details: details);
      await expectLater(platform.trackInstall(force: false), throwsA(matcher));
    }

    test('maps each native error code to its typed exception', () async {
      await expectMapped('invalidUrl', isA<LinkTrailInvalidUrlException>(), details: {'url': 'nope'});
      await expectMapped('transport', isA<LinkTrailTransportException>(), message: 'offline');
      await expectMapped('decoding', isA<LinkTrailDecodingException>(), message: 'bad json');
      await expectMapped('emptyResponse', isA<LinkTrailEmptyResponseException>());
      await expectMapped('notALinkTrailUrl', isA<LinkTrailNotALinkTrailUrlException>());
      await expectMapped('missingApiKey', isA<LinkTrailMissingApiKeyException>());
      await expectMapped('invalidApiKey', isA<LinkTrailInvalidApiKeyException>());
    });

    test('server errors carry status code and body', () async {
      native = (_) async => throw PlatformException(
        code: 'server',
        details: {'statusCode': 503, 'body': 'down'},
      );
      await expectLater(
        platform.trackEvent(name: 'e'),
        throwsA(
          isA<LinkTrailServerException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.body, 'body', 'down'),
        ),
      );
    });

    test('an unrecognised code maps to LinkTrailUnknownException', () async {
      await expectMapped('brand_new_code', isA<LinkTrailUnknownException>(), message: 'huh');
    });

    test('configure, handleDeepLink and trackInstallWithClickToken map errors too', () async {
      native = (_) async => throw PlatformException(code: 'invalidApiKey');
      await expectLater(
        platform.configure(apiKey: 'k', options: const LinkTrailOptions()),
        throwsA(isA<LinkTrailInvalidApiKeyException>()),
      );
      await expectLater(
        platform.handleDeepLink(Uri.parse('https://x.test')),
        throwsA(isA<LinkTrailInvalidApiKeyException>()),
      );
      await expectLater(
        platform.trackInstallWithClickToken('t', force: false),
        throwsA(isA<LinkTrailInvalidApiKeyException>()),
      );
    });
  });

  group('event streams', () {
    const onLink = EventChannel('linktrail_flutter/onLink');
    const onAttribution = EventChannel('linktrail_flutter/onAttribution');
    const onError = EventChannel('linktrail_flutter/onError');

    tearDown(() {
      messenger.setMockStreamHandler(onLink, null);
      messenger.setMockStreamHandler(onAttribution, null);
      messenger.setMockStreamHandler(onError, null);
    });

    test('onLink decodes deep links and their source', () async {
      messenger.setMockStreamHandler(
        onLink,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({
              'source': 'deferred',
              'link': {'slug': 'abc', 'deepLinkPath': '/p/1'},
            });
            events.success({
              'source': 'reengagement',
              'link': {'slug': 'def'},
            });
            events.endOfStream();
          },
        ),
      );

      final events = await platform.onLink.toList();
      expect(events, hasLength(2));
      expect(events[0].source, LinkTrailLinkSource.deferred);
      expect(events[0].link.slug, 'abc');
      expect(events[0].link.path, '/p/1');
      expect(events[1].source, LinkTrailLinkSource.reengagement);
      expect(events[1].link.path, '/');
    });

    test('onLink is a single shared broadcast stream', () {
      expect(platform.onLink.isBroadcast, isTrue);
      expect(identical(platform.onLink, platform.onLink), isTrue);
    });

    test('onLink surfaces a native stream error as a PlatformException', () async {
      messenger.setMockStreamHandler(
        onLink,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.error(code: 'boom', message: 'stream failed');
          },
        ),
      );
      await expectLater(platform.onLink, emitsError(isA<PlatformException>()));
    });

    test('onAttribution decodes attribution events', () async {
      messenger.setMockStreamHandler(
        onAttribution,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({'id': 9, 'attributed': true});
            events.endOfStream();
          },
        ),
      );
      final events = await platform.onAttribution.toList();
      expect(events.single.id, 9);
      expect(events.single.attributed, isTrue);
    });

    test('onError maps native error payloads to typed exceptions', () async {
      messenger.setMockStreamHandler(
        onError,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({'code': 'transport', 'message': 'offline'});
            events.success({
              'code': 'server',
              'message': 'x',
              'details': {'statusCode': 500},
            });
            events.endOfStream();
          },
        ),
      );
      final errors = await platform.onError.toList();
      expect(errors[0], isA<LinkTrailTransportException>());
      expect(errors[1], isA<LinkTrailServerException>().having((e) => e.statusCode, 'statusCode', 500));
    });
  });

  group('through the LinkTrail facade with the real platform', () {
    test('LinkTrail.trackEvent round-trips over the channel', () async {
      native = (_) async => {'id': 7, 'attributed': true};
      final result = await LinkTrail.trackEvent(name: 'purchase', value: 1, currency: 'EUR');
      expect(result.id, 7);
      expect(calls.single.arguments, {'name': 'purchase', 'value': 1.0, 'currency': 'EUR'});
    });
  });
}
