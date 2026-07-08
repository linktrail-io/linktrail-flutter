import 'package:flutter/foundation.dart';
import 'package:linktrail_flutter/linktrail_flutter.dart';

import 'catalog.dart';

sealed class Screen {
  const Screen();
}

class HomeScreen extends Screen {
  const HomeScreen();
}

class ProductDetailScreen extends Screen {
  const ProductDetailScreen(this.product, this.voucher);

  final Product product;
  final Voucher? voucher;
}

/// The whole demo's UI state, plus the **one** method the SDK integration
/// collapses into: [route]. Wired once via [LinkTrail.onLink]; the debug
/// simulator panel fires the same [LinkTrailDeepLink] objects into it —
/// mirrors the native KickFlip example apps' `Store`/`AttributionCoordinator`.
class Store extends ChangeNotifier {
  Screen screen = const HomeScreen();
  ProductCategory selectedProductCategory = ProductCategory.all;
  LinkTrailLinkSource? lastSource;

  void selectProductCategory(ProductCategory category) {
    selectedProductCategory = category;
    notifyListeners();
  }

  void openProduct(Product product) {
    screen = ProductDetailScreen(product, null);
    notifyListeners();
  }

  void goHome() {
    screen = const HomeScreen();
    notifyListeners();
  }

  /// The entire SDK surface the app touches: turn a deep link into a destination.
  void route(LinkTrailDeepLink link, LinkTrailLinkSource source) {
    lastSource = source;
    final path = link.path;

    if (path.startsWith('/products/')) {
      final id = path.substring(path.lastIndexOf('/') + 1);
      final product = Catalog.byId(id) ?? Catalog.products.first;
      final voucherCode = link.customData?['voucher'];
      final voucher = voucherCode == null
          ? null
          : Voucher(voucherCode, int.tryParse(link.customData?['discountPercent'] ?? '') ?? 0);
      screen = ProductDetailScreen(product, voucher);
    } else if (path.startsWith('/category/')) {
      final name = path.substring(path.lastIndexOf('/') + 1);
      selectedProductCategory = ProductCategory.values.firstWhere(
        (c) => c.label.toLowerCase() == name.toLowerCase(),
        orElse: () => ProductCategory.all,
      );
      screen = const HomeScreen();
    } else {
      selectedProductCategory = ProductCategory.all;
      screen = const HomeScreen();
    }

    notifyListeners();
  }

  /// Fire a scenario locally (no backend round-trip) — the simulator panel's point.
  void simulate(LinkTrailDeepLink link) => route(link, LinkTrailLinkSource.deferred);
}
