import 'package:flutter/material.dart';

import '../catalog.dart';
import '../store.dart';

class HomeScreenView extends StatelessWidget {
  const HomeScreenView({super.key, required this.store, this.status});

  final Store store;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final products = Catalog.byProductCategory(store.selectedProductCategory);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status case final status?) _StatusPill(status),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ProductCategory.values.map((category) {
                final selected = category == store.selectedProductCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => store.selectProductCategory(category),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.72,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) => _ProductCard(
              product: products[index],
              onTap: () => store.openProduct(products[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final isError = status.startsWith('Error') || status.contains('failed');
    final color = isError ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(product.icon, size: 56, color: scheme.primary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.category.label,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${product.price.toStringAsFixed(0)}',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
