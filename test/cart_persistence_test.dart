// QK-101: items removed / quantities reduced / coupons removed come back
// after the app is restarted, because those mutations were never saved.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

import 'helpers/test_harness.dart';

Product product(String id) => Product(
      id: id,
      name: id,
      categoryId: 'test',
      emoji: '🛒',
      unit: '1 pc',
      pricePaise: 5000,
      mrpPaise: 5000,
      stock: 20,
      maxPerOrder: 5,
    );

final coupon = Coupon(
  code: 'SAVE10',
  type: CouponType.percent,
  value: 10,
  minOrderPaise: 0,
  expiresAt: DateTime.utc(2099),
);

/// Does what main.dart does on a cold start: load the cart from storage.
Future<Cart> cartAfterRestart(TestHarness h) async {
  final restarted = h.restart();
  addTearDown(restarted.dispose);
  final saved = await restarted.read(cartStorageProvider).load();
  restarted.read(cartControllerProvider.notifier).hydrate(saved);
  return restarted.read(cartControllerProvider);
}

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('a reduced quantity survives a restart', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(product('milk'));
    await cart.increment('milk'); // 2
    await cart.decrement('milk'); // 1

    final restored = await cartAfterRestart(h);

    expect(restored.quantityOf('milk'), 1);
    expect(restored.totalQuantity, 1);
  });

  test('a line decremented to zero stays gone after a restart', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(product('chips'));
    await cart.decrement('chips'); // removes the line

    final restored = await cartAfterRestart(h);

    expect(restored.lineFor('chips'), isNull);
    expect(restored.isEmpty, isTrue);
  });

  test('a removed line stays gone after a restart', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(product('chips'));
    await cart.add(product('milk'));
    await cart.remove('chips');

    final restored = await cartAfterRestart(h);

    expect(restored.lineFor('chips'), isNull);
    expect(restored.quantityOf('milk'), 1);
  });

  test('a removed coupon stays removed after a restart', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(product('milk'));
    await cart.applyCoupon(coupon);
    await cart.removeCoupon();

    final restored = await cartAfterRestart(h);

    expect(restored.coupon, isNull);
  });
}
