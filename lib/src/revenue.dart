import 'errors.dart';

/// The result of a [LinkTrail.trackRevenue] call.
class LinkTrailRevenueResult {
  const LinkTrailRevenueResult({this.id, required this.attributed, this.duplicate = false});

  factory LinkTrailRevenueResult.fromMap(Map<Object?, Object?> map) {
    return LinkTrailRevenueResult(
      id: map['id'] as int?,
      attributed: map['attributed'] as bool,
      duplicate: map['duplicate'] as bool? ?? false,
    );
  }

  /// Server-side revenue event id; `null` when nothing was sent (for example a
  /// repeat already recorded on this install) or the server omitted it.
  final int? id;

  /// Whether the revenue was matched to a campaign click.
  final bool attributed;

  /// `true` when this transaction id was already recorded, so the repeat was
  /// ignored and nothing was double-counted.
  final bool duplicate;
}

/// Validated, normalised revenue arguments. Mirrors the native SDKs' rules:
/// ids and product ids are trimmed, the id is 1-255 characters, the value is
/// finite and >= 0, and the currency is 3 ASCII letters (uppercased).
class LinkTrailRevenueArgs {
  const LinkTrailRevenueArgs._(this.transactionId, this.value, this.currency, this.productId);

  /// Throws [LinkTrailInvalidRevenueException] if any argument is invalid.
  factory LinkTrailRevenueArgs.validate({
    required String transactionId,
    required double value,
    required String currency,
    String? productId,
  }) {
    final txn = transactionId.trim();
    if (txn.isEmpty || txn.length > 255) {
      throw const LinkTrailInvalidRevenueException('Revenue transactionId must be 1-255 characters.');
    }
    if (!value.isFinite || value < 0) {
      throw const LinkTrailInvalidRevenueException('Revenue value must be a finite number >= 0.');
    }
    final code = currency.trim();
    if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(code)) {
      throw const LinkTrailInvalidRevenueException('Revenue currency must be a 3-letter ISO 4217 code (e.g. "USD").');
    }
    final product = productId?.trim();
    return LinkTrailRevenueArgs._(
      txn,
      value,
      code.toUpperCase(),
      (product == null || product.isEmpty) ? null : product,
    );
  }

  final String transactionId;
  final double value;
  final String currency;
  final String? productId;
}
