// Shows how to drive the mock backend from tests. Use the same approach for
// your own tests (and for the "failing test first" evidence of each bug).
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/data/order_api.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('categories are served by the mock server', () async {
    final categories =
        await h.read(catalogRepositoryProvider).getCategories();
    expect(categories, isNotEmpty);
  });

  test('an order with correct prices is accepted', () async {
    // fruits-01 = Robusta Banana, ₹49 in variant A.
    final banana = h.server.product('fruits-01');
    final cart = Cart(lines: [
      CartLine(
        productId: banana.id,
        name: banana.name,
        emoji: '🍌',
        unit: '6 pcs',
        unitPricePaise: banana.pricePaise,
        quantity: 2,
        maxPerOrder: banana.maxPerOrder,
      ),
    ]);
    final pricing = CartPricing.compute(cart, AppConfig.defaults());

    final order = await h.read(orderApiProvider).placeOrder(cart, pricing);

    expect(order.totalPaise, pricing.totalPaise);
    expect(h.server.orderCount, 1);
  });

  test('the server rejects orders with an outdated price', () async {
    final banana = h.server.product('fruits-01');
    final cart = Cart(lines: [
      CartLine(
        productId: banana.id,
        name: banana.name,
        emoji: '🍌',
        unit: '6 pcs',
        unitPricePaise: banana.pricePaise,
        quantity: 1,
        maxPerOrder: banana.maxPerOrder,
      ),
    ]);
    h.server.setPrice(banana.id, banana.pricePaise + 500);

    await expectLater(
      h
          .read(orderApiProvider)
          .placeOrder(cart, CartPricing.compute(cart, AppConfig.defaults())),
      throwsA(isA<ClientException>()
          .having((e) => e.code, 'code', 'PRICE_CHANGED')),
    );
    expect(h.server.orderCount, 0);
  });

  test('offline requests fail with NetworkException', () async {
    h.server.chaos.offline = true;
    await expectLater(
      h.read(catalogRepositoryProvider).getCategories(),
      throwsA(isA<NetworkException>()),
    );
  });
}
