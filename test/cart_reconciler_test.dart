import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;
  late CartReconciler reconciler;

  setUp(() {
    h = TestHarness();
    reconciler = h.container.read(cartReconcilerProvider);
  });
  tearDown(() => h.dispose());

  test('empty cart reconciles to empty cart with no changes', () async {
    final result = await reconciler.reconcile(const Cart.empty());
    expect(result.cart.isEmpty, isTrue);
    expect(result.changes, isEmpty);
    expect(result.hasChanges, isFalse);
    expect(result.requiresUserReview, isFalse);
  });

  test('unchanged cart returns empty changes and equal cart', () async {
    final p1 = h.server.products[0];
    final p2 = h.server.products[1];
    final cart = Cart(lines: [
      CartLine.fromProduct(p1, quantity: 2),
      CartLine.fromProduct(p2, quantity: 1),
    ]);

    final result = await reconciler.reconcile(cart);
    expect(result.changes, isEmpty);
    expect(result.cart, equals(cart));
    expect(result.requiresUserReview, isFalse);
  });

  test('price increase records PriceChanged and requiresUserReview', () async {
    final p = h.server.products[0];
    final cart = Cart(lines: [CartLine.fromProduct(p, quantity: 1)]);

    // Server increases price
    h.server.setPrice(p.id, p.pricePaise + 1000);

    final result = await reconciler.reconcile(cart);
    expect(result.changes.length, 1);
    final change = result.changes.first as PriceChanged;
    expect(change.productId, p.id);
    expect(change.oldPricePaise, p.pricePaise);
    expect(change.newPricePaise, p.pricePaise + 1000);
    expect(change.isIncrease, isTrue);
    expect(change.requiresUserReview, isTrue);
    expect(result.requiresUserReview, isTrue);
    expect(result.cart.lines.first.unitPricePaise, p.pricePaise + 1000);
  });

  test('price drop records PriceChanged but does NOT require user review',
      () async {
    final p = h.server.products[0];
    final cart = Cart(lines: [CartLine.fromProduct(p, quantity: 1)]);

    // Server decreases price
    h.server.setPrice(p.id, p.pricePaise - 500);

    final result = await reconciler.reconcile(cart);
    expect(result.changes.length, 1);
    final change = result.changes.first as PriceChanged;
    expect(change.isIncrease, isFalse);
    expect(change.requiresUserReview, isFalse);
    expect(result.requiresUserReview, isFalse);
    expect(result.cart.lines.first.unitPricePaise, p.pricePaise - 500);
  });

  test('out of stock items are removed and require review', () async {
    final p1 = h.server.products[0];
    final p2 = h.server.products[1];
    final cart = Cart(lines: [
      CartLine.fromProduct(p1, quantity: 1),
      CartLine.fromProduct(p2, quantity: 2),
    ]);

    // p1 runs out of stock
    h.server.setStock(p1.id, 0);

    final result = await reconciler.reconcile(cart);
    expect(result.changes.length, 1);
    expect(result.changes.first, isA<OutOfStock>());
    expect((result.changes.first as OutOfStock).productId, p1.id);
    expect(result.requiresUserReview, isTrue);
    expect(result.cart.lines.length, 1);
    expect(result.cart.lines.first.productId, p2.id);
  });

  test('discontinued/missing items are removed and require review', () async {
    final p1 = h.server.products[0];
    final p2 = h.server.products[1];
    final cart = Cart(lines: [
      CartLine.fromProduct(p1, quantity: 1),
      CartLine.fromProduct(p2, quantity: 2),
    ]);

    // Deactivate p1 on server (returns in missingIds)
    h.server.setActive(p1.id, false);

    final result = await reconciler.reconcile(cart);
    expect(result.changes.length, 1);
    expect(result.changes.first, isA<ProductUnavailable>());
    expect((result.changes.first as ProductUnavailable).productId, p1.id);
    expect(result.requiresUserReview, isTrue);
    expect(result.cart.lines.length, 1);
    expect(result.cart.lines.first.productId, p2.id);
  });

  test('quantity exceeding available stock or maxPerOrder is reduced', () async {
    final p = h.server.products[0];
    // Line wants 5, max was 5
    final cart = Cart(lines: [CartLine.fromProduct(p, quantity: 5)]);

    // Server reduces stock to 2
    h.server.setStock(p.id, 2);

    final result = await reconciler.reconcile(cart);
    expect(result.changes.length, 1);
    final change = result.changes.first as QuantityReduced;
    expect(change.productId, p.id);
    expect(change.requestedQuantity, 5);
    expect(change.availableQuantity, 2);
    expect(change.requiresUserReview, isTrue);
    expect(result.cart.lines.first.quantity, 2);
    expect(result.cart.lines.first.maxPerOrder, 2);
  });

  test('expired coupon is removed and records CouponRemoved', () async {
    final p = h.server.products[0];
    final expiredCoupon = Coupon(
      code: 'EXPIRED10',
      type: CouponType.percent,
      value: 10,
      minOrderPaise: 0,
      expiresAt: DateTime.utc(2020),
    );
    final cart = Cart(
      lines: [CartLine.fromProduct(p, quantity: 1)],
      coupon: expiredCoupon,
    );

    final result = await reconciler.reconcile(cart);
    expect(result.cart.coupon, isNull);
    expect(result.changes.any((c) => c is CouponRemoved), isTrue);
    expect(result.requiresUserReview, isTrue);
  });

  test('unknown coupon is removed and records CouponRemoved with NOT_FOUND',
      () async {
    final p = h.server.products[0];
    final unknownCoupon = Coupon(
      code: 'UNKNOWN99',
      type: CouponType.flat,
      value: 5000,
      minOrderPaise: 0,
      expiresAt: DateTime.utc(2099),
    );
    final cart = Cart(
      lines: [CartLine.fromProduct(p, quantity: 1)],
      coupon: unknownCoupon,
    );

    final result = await reconciler.reconcile(cart);
    expect(result.cart.coupon, isNull);
    final removed =
        result.changes.firstWhere((c) => c is CouponRemoved) as CouponRemoved;
    expect(removed.code, 'UNKNOWN99');
    expect(removed.reason, 'NOT_FOUND');
    expect(result.requiresUserReview, isTrue);
  });

  test('coupon below minimum order stays in cart without CouponRemoved',
      () async {
    final p = h.server.products[0];
    // SAVE10 has minOrderPaise: 19900
    final coupon = await h.container.read(couponApiProvider).validate('SAVE10');
    // cart with 1 unit of p (price ~5000 paise < 19900)
    final cart = Cart(
      lines: [CartLine.fromProduct(p, quantity: 1)],
      coupon: coupon,
    );

    final result = await reconciler.reconcile(cart);
    expect(result.cart.coupon?.code, 'SAVE10');
    expect(result.changes.any((c) => c is CouponRemoved), isFalse);
  });

  test('reconcile preserves original line order', () async {
    final p0 = h.server.products[0];
    final p1 = h.server.products[1];
    final p2 = h.server.products[2];
    final cart = Cart(lines: [
      CartLine.fromProduct(p2),
      CartLine.fromProduct(p0),
      CartLine.fromProduct(p1),
    ]);

    final result = await reconciler.reconcile(cart);
    expect(result.cart.lines.map((l) => l.productId).toList(), [
      p2.id,
      p0.id,
      p1.id,
    ]);
  });

  test('throws ApiException when server is unreachable', () async {
    final p = h.server.products[0];
    final cart = Cart(lines: [CartLine.fromProduct(p)]);
    h.server.chaos.offline = true;

    expect(() => reconciler.reconcile(cart), throwsA(isA<ApiException>()));
  });
}
