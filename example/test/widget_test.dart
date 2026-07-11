// Basic smoke test for the KickFlip example app.

import 'package:flutter_test/flutter_test.dart';

import 'package:linktrail_flutter_example/main.dart';

void main() {
  testWidgets('KickFlip renders the storefront title', (WidgetTester tester) async {
    await tester.pumpWidget(const KickFlipDemoApp());
    await tester.pump();

    expect(find.text('KickFlip'), findsOneWidget);
  });
}
