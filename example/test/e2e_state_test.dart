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

  test('parseEvents reads names and name,value,currency entries', () {
    final events = E2EState.parseEvents('purchase; purchase;e2e_other');
    expect(events?.map((e) => e.name), ['purchase', 'purchase', 'e2e_other']);
    expect(events?.first.value, isNull);

    final revenue = E2EState.parseEvents('e2e_revenue,19.99,GBP;e2e_revenue,19.99,USD');
    expect(revenue?.length, 2);
    expect(revenue?.first.value, 19.99);
    expect(revenue?.last.currency, 'USD');
  });

  test('parseEvents rejects malformed specs', () {
    for (final spec in ['', ' ; ', 'a,1', 'a,x,GBP', 'a,1,', ',1,GBP', 'a,1,GBP,extra']) {
      expect(E2EState.parseEvents(spec), isNull, reason: spec);
    }
  });

  test('formatEvents is the tally the reward flows assert', () {
    expect(E2EState.formatEvents(requested: 3, sent: 0, attributed: 0, failed: 0), 'requested 3 sent 0 attributed 0 failed 0');
  });

  test('recordAttribution and recordEvents update the panel state', () {
    final state = E2EState();
    expect(state.attribution, 'none');
    state.recordAttribution(const LinkTrailAttribution(attributed: false));
    expect(state.attribution, 'attributed=false');
    state.recordEvents('requested 1 sent 1 attributed 1 failed 0');
    expect(state.events, 'requested 1 sent 1 attributed 1 failed 0');
  });
}
