import 'package:flutter/material.dart';

enum ProductCategory { all, running, lifestyle }

extension ProductCategoryLabel on ProductCategory {
  String get label => switch (this) {
    ProductCategory.all => 'All',
    ProductCategory.running => 'Running',
    ProductCategory.lifestyle => 'Lifestyle',
  };
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.icon,
  });

  final String id;
  final String name;
  final ProductCategory category;
  final double price;
  final IconData icon;
}

class Voucher {
  const Voucher(this.code, this.discountPercent);

  final String code;
  final int discountPercent;
}

/// The KickFlip demo storefront's catalog — mirrors the native Android/iOS
/// KickFlip example apps so the same `/products/aj1` deep links resolve to
/// the same product everywhere.
abstract final class Catalog {
  static const products = [
    Product(id: 'aj1', name: 'Air Jordan 1', category: ProductCategory.running, price: 180, icon: Icons.directions_run),
    Product(
      id: 'db2',
      name: 'Dunk Low',
      category: ProductCategory.lifestyle,
      price: 120,
      icon: Icons.skateboarding,
    ),
    Product(id: 'af3', name: 'Air Force 3', category: ProductCategory.running, price: 140, icon: Icons.directions_run),
    Product(id: 'cx4', name: 'Classic Canvas', category: ProductCategory.lifestyle, price: 65, icon: Icons.style),
  ];

  static Product? byId(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  static List<Product> byProductCategory(ProductCategory category) {
    if (category == ProductCategory.all) return products;
    return products.where((p) => p.category == category).toList();
  }
}
