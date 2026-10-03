import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter/linktrail_flutter_method_channel.dart';
import 'package:linktrail_flutter/linktrail_flutter_platform_interface.dart';
import 'package:linktrail_flutter/src/user_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('linktrail_flutter');
  final calls = <MethodCall>[];
  String? stored; // plays the native persisted store (survives "restarts")

  setUp(() {
    calls.clear();
    LinktrailFlutterPlatform.instance = MethodChannelLinktrailFlutter();
    UserIdentity.resetConsentForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'setUserId':
          stored = call.arguments['userId'] as String?;
          return null;
        case 'getUserId':
          return stored;
      }
      return null;
    });
    stored = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  List<MethodCall> setCalls() => calls.where((c) => c.method == 'setUserId').toList();

  group('validation', () {
    test('accepts allowed characters and boundary lengths', () async {
      for (final id in ['a', 'user_1-2.3:4', 'A' * 128]) {
        await LinkTrail.setUserId(id);
      }
      expect(setCalls(), hasLength(3));
    });

    test('rejects invalid ids without storing or sending', () async {
      for (final id in ['', 'a' * 129, 'a b', 'me@example.com', '+15551234', 'naïve', 'a/b']) {
        await expectLater(LinkTrail.setUserId(id), throwsArgumentError, reason: id);
      }
      expect(calls, isEmpty);
      expect(stored, isNull);
    });
  });

  group('persistence', () {
    test('stored id is readable and replaced by a different id', () async {
      await LinkTrail.setUserId('u1');
      expect(await LinkTrail.userId, 'u1');
      await LinkTrail.setUserId('u2');
      expect(await LinkTrail.userId, 'u2');
    });

    test('configure restores the persisted id into the native layer', () async {
      stored = 'persisted';
      await LinkTrail.configure(apiKey: 'lt_test');
      expect(setCalls().single.arguments, {'userId': 'persisted', 'consented': false});
    });
  });

  group('consent gating', () {
    test('setUserId without consent is stored but flagged not consented', () async {
      await LinkTrail.setUserId('u1');
      expect(setCalls().single.arguments, {'userId': 'u1', 'consented': false});
      await LinkTrail.setConsent(false);
      await LinkTrail.setUserId('u2');
      expect(setCalls().last.arguments, {'userId': 'u2', 'consented': false});
    });

    test('granting consent re-applies a stored id as consented', () async {
      await LinkTrail.setUserId('u1');
      calls.clear();
      await LinkTrail.setConsent(true);
      expect(setCalls().single.arguments, {'userId': 'u1', 'consented': true});
    });

    test('granting consent with no stored id sends nothing', () async {
      await LinkTrail.setConsent(true);
      expect(setCalls(), isEmpty);
    });

    test('setUserId after consent is flagged consented', () async {
      await LinkTrail.setConsent(true);
      await LinkTrail.setUserId('u1');
      expect(setCalls().single.arguments, {'userId': 'u1', 'consented': true});
    });

    test('denying consent does not re-apply the id', () async {
      await LinkTrail.setUserId('u1');
      calls.clear();
      await LinkTrail.setConsent(false);
      expect(setCalls(), isEmpty);
    });
  });

  group('logout', () {
    test('clears the persisted id and sends a null userId', () async {
      await LinkTrail.setConsent(true);
      await LinkTrail.setUserId('u1');
      await LinkTrail.logout();
      expect(setCalls().last.arguments, {'userId': null, 'consented': true});
      expect(await LinkTrail.userId, isNull);
    });

    test('a later consent grant does not resurrect a logged-out id', () async {
      await LinkTrail.setUserId('u1');
      await LinkTrail.logout();
      calls.clear();
      await LinkTrail.setConsent(true);
      expect(setCalls(), isEmpty);
    });
  });
}
