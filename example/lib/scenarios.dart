import 'package:linktrail_flutter/linktrail_flutter.dart';

/// One of the demo's deferred-deep-link scenarios — the same four scenarios
/// the native Android/iOS KickFlip example apps fire from their debug panel.
class DeepLinkScenario {
  const DeepLinkScenario({required this.title, required this.subtitle, required this.link});

  final String title;
  final String subtitle;
  final LinkTrailDeepLink link;
}

final List<DeepLinkScenario> deepLinkScenarios = [
  const DeepLinkScenario(
    title: 'Just the store',
    subtitle: 'deepLinkPath: "/" → Home',
    link: LinkTrailDeepLink(deepLinkPath: '/', campaign: 'brand-awareness'),
  ),
  const DeepLinkScenario(
    title: 'Category selected',
    subtitle: 'deepLinkPath: "/category/running" → Home, Running pre-selected',
    link: LinkTrailDeepLink(deepLinkPath: '/category/running', campaign: 'running-sale'),
  ),
  const DeepLinkScenario(
    title: 'A product',
    subtitle: 'deepLinkPath: "/products/aj1" → Air Jordan 1',
    link: LinkTrailDeepLink(deepLinkPath: '/products/aj1', campaign: 'aj1-launch'),
  ),
  const DeepLinkScenario(
    title: 'Product + voucher',
    subtitle: '"/products/aj1" + customData {voucher: SUMMER25, 25%}',
    link: LinkTrailDeepLink(
      deepLinkPath: '/products/aj1',
      campaign: 'vip-loyalty',
      customData: {'voucher': 'SUMMER25', 'discountPercent': '25'},
    ),
  ),
];
