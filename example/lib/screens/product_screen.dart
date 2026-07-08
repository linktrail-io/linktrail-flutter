import 'package:flutter/material.dart';

import '../catalog.dart';

class ProductScreenView extends StatelessWidget {
  const ProductScreenView({super.key, required this.product, required this.voucher});

  final Product product;
  final Voucher? voucher;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasVoucher = voucher != null;
    final discounted = hasVoucher ? product.price * (100 - voucher!.discountPercent) / 100 : product.price;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero icon.
                Container(
                  height: 280,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(product.icon, size: 130, color: scheme.primary),
                ),
                const SizedBox(height: 24),
                Text(product.category.label.toUpperCase(),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(product.name,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                // Price row.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('\$${discounted.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: scheme.primary)),
                    if (hasVoucher) ...[
                      const SizedBox(width: 10),
                      Text('\$${product.price.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade400,
                              decoration: TextDecoration.lineThrough)),
                    ],
                  ],
                ),
                if (hasVoucher) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.local_offer_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Voucher ${voucher!.code} applied — save ${voucher!.discountPercent}%',
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Arrived here via a LinkTrail deep link. This is the destination the SDK routed to '
                  'from the tapped link — path, voucher and all.',
                  style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        // Bottom action bar — padded for the gesture area so it never clips.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEDEBF5))),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Add to cart', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }
}
