import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/product.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({
    required this.catalogApi,
    required this.couponApi,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CatalogApi catalogApi;
  final CouponApi couponApi;
  final DateTime Function() _clock;

  /// Returns a [ReconciliationResult] whose `cart` is what could be ordered
  /// right now.
  ///
  /// * every line's `unitPricePaise` equals the server's current price;
  /// * every line's `quantity` is `<= min(stock, maxPerOrder)` and its
  ///   `maxPerOrder` is refreshed to that same value;
  /// * lines whose product is out of stock or no longer sold are removed;
  /// * the coupon is removed if it is expired or unknown, otherwise refreshed;
  /// * the order of the remaining lines is preserved.
  ///
  /// Throws an [ApiException] if the server cannot be reached. Never returns
  /// a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    if (cart.isEmpty) {
      return const ReconciliationResult(cart: Cart.empty(), changes: []);
    }

    // Fetch latest catalog details in chunks of 50 (batch endpoint limit).
    final ids = cart.lines.map((l) => l.productId).toList();
    final products = <String, Product>{};
    final missing = <String>{};

    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.sublist(i, min(i + 50, ids.length));
      final batch = await catalogApi.getProductsByIds(chunk);
      for (final p in batch.products) {
        products[p.id] = p;
      }
      missing.addAll(batch.missingIds);
    }

    final changes = <CartChange>[];
    final reconciledLines = <CartLine>[];

    for (final line in cart.lines) {
      final product = products[line.productId];
      if (product == null || missing.contains(line.productId)) {
        changes.add(ProductUnavailable(productId: line.productId));
        continue;
      }

      if (!product.inStock) {
        changes.add(OutOfStock(productId: line.productId));
        continue;
      }

      final maxAllowed = min(product.stock, product.maxPerOrder);
      var qty = line.quantity;
      if (qty > maxAllowed) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: qty,
          availableQuantity: maxAllowed,
        ));
        qty = maxAllowed;
      }

      if (product.pricePaise != line.unitPricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: product.pricePaise,
        ));
      }

      reconciledLines.add(line.copyWith(
        name: product.name,
        unitPricePaise: product.pricePaise,
        quantity: qty,
        maxPerOrder: maxAllowed,
      ));
    }

    // Refresh or drop coupon.
    Coupon? refreshedCoupon = cart.coupon;
    if (cart.coupon != null) {
      try {
        final latest = await couponApi.validate(cart.coupon!.code);
        if (latest.isExpired(_clock())) {
          changes.add(
            CouponRemoved(code: cart.coupon!.code, reason: 'EXPIRED'),
          );
          refreshedCoupon = null;
        } else {
          refreshedCoupon = latest;
        }
      } on ClientException catch (e) {
        if (e.code == 'COUPON_NOT_FOUND' || e.statusCode == 404) {
          changes.add(
            CouponRemoved(code: cart.coupon!.code, reason: 'NOT_FOUND'),
          );
          refreshedCoupon = null;
        } else if (e.code == 'COUPON_EXPIRED' || e.statusCode == 409) {
          changes.add(
            CouponRemoved(code: cart.coupon!.code, reason: 'EXPIRED'),
          );
          refreshedCoupon = null;
        } else {
          rethrow;
        }
      }
    }

    return ReconciliationResult(
      cart: Cart(lines: reconciledLines, coupon: refreshedCoupon),
      changes: changes,
    );
  }
}
