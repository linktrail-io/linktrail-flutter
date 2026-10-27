import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('linktrail_flutter');

  Map<String, Object?> linkMap(String slug) => {'slug': slug, 'url': 'https://linktrail.io/l/$slug'};

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(const EventChannel('linktrail_flutter/onLink'), null);
    messenger.setMockStreamHandler(const EventChannel('linktrail_flutter/onAttribution'), null);
  });

  group('resolveDeepLink', () {
    test('returns the resolved link', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return linkMap('promo');
      });
      final link = await MethodChannelLinktrailFlutter().resolveDeepLink(Uri.parse('https://linktrail.io/l/promo'));
      expect(seen!.method, 'resolveDeepLink');
      expect(seen!.arguments['url'], 'https://linktrail.io/l/promo');
      expect(link!.slug, 'promo');
    });

    test('returns null for a non-LinkTrail URL', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await MethodChannelLinktrailFlutter().resolveDeepLink(Uri.parse('myapp://settings')), isNull);
    });

    test('throws a server error with statusCode, body and the native message', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'server',
          message: 'Server returned status 503: down',
          details: {'statusCode': 503, 'body': 'down'},
        );
      });
      final future = MethodChannelLinktrailFlutter().resolveDeepLink(Uri.parse('https://linktrail.io/l/x'));
      await expectLater(
        future,
        throwsA(
          isA<LinkTrailServerException>()
              .having((e) => e.code, 'code', 'server')
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.body, 'body', 'down')
              .having((e) => e.message, 'message', 'Server returned status 503: down'),
        ),
      );
    });

    test('keeps handleDeepLink returning a bool', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'handleDeepLink');
      expect(await MethodChannelLinktrailFlutter().handleDeepLink(Uri.parse('https://linktrail.io/l/x')), isTrue);
    });
  });

  group('error codes', () {
    const cases = {
      'missingApiKey': LinkTrailMissingApiKeyException,
      'invalidApiKey': LinkTrailInvalidApiKeyException,
      'notConfigured': LinkTrailNotConfiguredException,
      'invalidUrl': LinkTrailInvalidUrlException,
      'notALinkTrailUrl': LinkTrailNotALinkTrailUrlException,
      'transport': LinkTrailTransportException,
      'server': LinkTrailServerException,
      'decoding': LinkTrailDecodingException,
      'emptyResponse': LinkTrailEmptyResponseException,
      'invalidArgument': LinkTrailInvalidArgumentException,
    };
    for (final entry in cases.entries) {
      test('${entry.key} maps to ${entry.value} and keeps the native message', () {
        final e = LinkTrailException.fromPlatformException(PlatformException(code: entry.key, message: 'native says'));
        expect(e.runtimeType, entry.value);
        expect(e.code, entry.key);
        expect(e.message, 'native says');
      });
    }

    test('an unknown code is kept on LinkTrailUnknownException', () {
      final e = LinkTrailException.fromPlatformException(PlatformException(code: 'weird', message: 'm'));
      expect(e, isA<LinkTrailUnknownException>());
      expect(e.code, 'weird');
    });
  });

  group('onLink delivery', () {
    test('links the native side held before listening reach the first listener in order', () async {
      // The native plugin flushes its buffer as soon as Dart starts listening.
      messenger.setMockStreamHandler(
        const EventChannel('linktrail_flutter/onLink'),
        MockStreamHandler.inline(
          onListen: (args, sink) {
            sink.success({'link': linkMap('a'), 'source': 'deferred'});
            sink.success({'link': linkMap('b'), 'source': 'reengagement'});
          },
        ),
      );
      final events = await MethodChannelLinktrailFlutter().onLink.take(2).toList();
      expect(events.map((e) => e.link.slug), ['a', 'b']);
      expect(events.map((e) => e.source), [LinkTrailLinkSource.deferred, LinkTrailLinkSource.reengagement]);
    });

    test('re-listening after a cancel receives a link native claimed in between', () async {
      MockStreamHandlerEventSink? current;
      var listens = 0;
      messenger.setMockStreamHandler(
        const EventChannel('linktrail_flutter/onLink'),
        MockStreamHandler.inline(
          onListen: (args, sink) {
            listens++;
            current = sink;
            // Second listen: the native relay replays what arrived while detached.
            if (listens == 2) sink.success({'link': linkMap('held'), 'source': 'deferred'});
          },
        ),
      );
      final platform = MethodChannelLinktrailFlutter();
      final first = platform.onLink.listen((_) {});
      await pumpEventQueue();
      await first.cancel();
      await pumpEventQueue();

      final got = Completer<LinkTrailLinkEvent>();
      final second = platform.onLink.listen(got.complete);
      final event = await got.future;
      expect(event.link.slug, 'held');
      expect(listens, 2);
      expect(current, isNotNull);
      await second.cancel();
    });

    test('attribution replayed by native reaches the first listener', () async {
      messenger.setMockStreamHandler(
        const EventChannel('linktrail_flutter/onAttribution'),
        MockStreamHandler.inline(onListen: (args, sink) => sink.success({'attributed': true, 'id': 7})),
      );
      final a = await MethodChannelLinktrailFlutter().onAttribution.first;
      expect(a.attributed, isTrue);
    });
  });

  test('autoHandleLinks defaults to true and is sent to native', () {
    expect(const LinkTrailOptions().toMap()['autoHandleLinks'], isTrue);
    expect(const LinkTrailOptions(autoHandleLinks: false).toMap()['autoHandleLinks'], isFalse);
  });
}
