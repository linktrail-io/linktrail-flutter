import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';

void main() {
  test('linkTrailFlutterVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(linkTrailFlutterVersion, version);
  });

  test('LinkTrailDeepLink keeps nested customData as a JSON string', () {
    final link = LinkTrailDeepLink.fromMap({
      'customData': {'voucher': 'SUMMER25', 'tags': '["a","b"]'},
    });
    expect(link.customData, {'voucher': 'SUMMER25', 'tags': '["a","b"]'});
  });
}
