// Basic integration test: exercises the plugin's platform channel end to end on a real
// host (device/simulator). Since no API key is configured here, trackEvent is expected to
// surface a LinkTrailException — which still proves the Dart → native → Dart round-trip works.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:linktrail_flutter/linktrail_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trackEvent reaches the native SDK', (WidgetTester tester) async {
    await expectLater(
      LinkTrail.trackEvent(name: 'integration_test_event'),
      throwsA(isA<LinkTrailException>()),
    );
  });
}
