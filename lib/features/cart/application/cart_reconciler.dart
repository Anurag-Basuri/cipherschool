import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// ## TODO(F1) - implement
  ///
  /// Contract (checked by hidden tests - see ASSIGNMENT.md, Feature 1):
  ///
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
    throw UnimplementedError('F1: implement CartReconciler.reconcile');
  }
}
