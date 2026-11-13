import 'package:flutter_test/flutter_test.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';
import 'package:linktrail_flutter_example/e2e.dart';

void main() {
  test('formatCustomData sorts pairs and handles empty data', () {
    expect(E2EState.formatCustomData(null), 'none');
    expect(E2EState.formatCustomData({}), 'none');
    expect(E2EState.formatCustomData({'voucher': 'SUMMER25', 'discountPercent': '25'}),
        'discountPercent=25, voucher=SUMMER25');
  });

  test('recordLink counts every delivery', () {
    final state = E2EState();
    const event = LinkTrailLinkEvent(LinkTrailDeepLink(deepLinkPath: '/products/aj1'), LinkTrailLinkSource.deferred);
    state.recordLink(event);
    state.recordLink(event);
    expect(state.linkCount, 2);
    expect(state.lastLink?.link.path, '/products/aj1');
  });
}
