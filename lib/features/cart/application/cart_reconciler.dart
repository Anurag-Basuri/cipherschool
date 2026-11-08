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
  /// right now:
  /// * every line's `unitPricePaise` equals the server's current price;
  /// * every line's `quantity` is `<= min(stock, maxPerOrder)` and its
  ///   `maxPerOrder` is refreshed to that same value;
  /// * lines whose product is out of stock or no longer sold are removed;
  /// * the coupon is removed if it is expired or unknown, otherwise it is
  ///   refreshed with the server's latest rules (a coupon whose minimum
  ///   order is not met stays in the cart - see BUSINESS_RULES.md);
  /// * the order of the remaining lines is preserved.
  ///
  /// `changes` lists every difference (one [CartChange] per product/coupon
  /// issue). An unchanged cart returns an empty list and an equal cart.
  ///
  /// Throws an `ApiException` if the server cannot be reached. It must never
  /// return a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    final changes = <CartChange>[];

    // 1. Fetch latest product data in batches of at most 50
    final productIds = cart.lines.map((l) => l.productId).toList();
    final serverProducts = <String, Product>{};
    final missingIds = <String>{};

    for (var i = 0; i < productIds.length; i += 50) {
      final chunk = productIds.sublist(i, min(i + 50, productIds.length));
      final batch = await catalogApi.getProductsByIds(chunk);
      for (final p in batch.products) {
        serverProducts[p.id] = p;
      }
      missingIds.addAll(batch.missingIds);
    }

    // 2. Reconcile each line preserving original order
    final newLines = <CartLine>[];
    for (final line in cart.lines) {
      if (missingIds.contains(line.productId) ||
          !serverProducts.containsKey(line.productId)) {
        changes.add(ProductUnavailable(productId: line.productId));
        continue;
      }

      final serverProduct = serverProducts[line.productId]!;
      if (serverProduct.stock <= 0) {
        changes.add(OutOfStock(productId: line.productId));
        continue;
      }

      final available = min(serverProduct.stock, serverProduct.maxPerOrder);
      var quantity = line.quantity;
      if (quantity > available) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: line.quantity,
          availableQuantity: available,
        ));
        quantity = available;
      }

      if (serverProduct.pricePaise != line.unitPricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: serverProduct.pricePaise,
        ));
      }

      newLines.add(line.copyWith(
        name: serverProduct.name,
        unitPricePaise: serverProduct.pricePaise,
        quantity: quantity,
        maxPerOrder: available,
      ));
    }

    // 3. Reconcile coupon if present
    Coupon? newCoupon = cart.coupon;
    if (cart.coupon != null) {
      try {
        final validated = await couponApi.validate(cart.coupon!.code);
        if (validated.isExpired(_clock())) {
          changes
              .add(CouponRemoved(code: cart.coupon!.code, reason: 'EXPIRED'));
          newCoupon = null;
        } else {
          newCoupon = validated;
        }
      } on ClientException catch (e) {
        if (e.code == 'COUPON_NOT_FOUND' || e.statusCode == 404) {
          changes.add(
              CouponRemoved(code: cart.coupon!.code, reason: 'NOT_FOUND'));
          newCoupon = null;
        } else if (e.code == 'COUPON_EXPIRED' || e.statusCode == 409) {
          changes
              .add(CouponRemoved(code: cart.coupon!.code, reason: 'EXPIRED'));
          newCoupon = null;
        } else {
          rethrow;
        }
      }
    }

    final newCart = Cart(lines: newLines, coupon: newCoupon);
    return ReconciliationResult(cart: newCart, changes: changes);
  }
}
