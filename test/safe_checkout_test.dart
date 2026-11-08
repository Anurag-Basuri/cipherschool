import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('store closed guard returns CheckoutFailure and sends no network request',
      () async {
    // Set store closed
    h.server.publishConfig({'store_open': false});
    final config = await h.container.read(configRepositoryProvider).load();
    h.container.read(appConfigControllerProvider.notifier).hydrate(config);

    // Add item to cart
    final p = h.server.products.first;
    await h.container.read(cartControllerProvider.notifier).add(p);

    final result = await h.container
        .read(checkoutControllerProvider.notifier)
        .placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect(
      h.server.requestLog.where((r) => r.path == '/v1/orders'),
      isEmpty,
    );
  });

  test('placing order sends an Idempotency-Key header', () async {
    final p = h.server.products.first;
    await h.container.read(cartControllerProvider.notifier).add(p);

    final result = await h.container
        .read(checkoutControllerProvider.notifier)
        .placeOrder();

    expect(result, isA<CheckoutSuccess>());
    final orderRequests =
        h.server.requestLog.where((r) => r.path == '/v1/orders').toList();
    expect(orderRequests, isNotEmpty);
    final idempKey = orderRequests.first.headers['Idempotency-Key'];
    expect(idempKey, isNotNull);
    expect(idempKey!.isNotEmpty, isTrue);
  });

  test('lost order response does not create duplicate orders on retry',
      () async {
    final p = h.server.products.first;
    await h.container.read(cartControllerProvider.notifier).add(p);

    // Simulate lost order response: server creates the order, but response is lost
    h.server.chaos.lostOrderResponses = 1;

    final result = await h.container
        .read(checkoutControllerProvider.notifier)
        .placeOrder();

    // The automatic retry should recover the order created by the first attempt
    expect(result, isA<CheckoutSuccess>());

    // Verify on the server that exactly one order exists
    final orders = await h.server.getOrders();
    expect(orders.length, 1);
  });

  test('reconciliation detects changes before order is placed and returns CheckoutNeedsReview',
      () async {
    final p = h.server.products.first;
    await h.container.read(cartControllerProvider.notifier).add(p);

    // Price changes on server before checkout
    h.server.setPrice(p.id, p.pricePaise + 2000);

    final result = await h.container
        .read(checkoutControllerProvider.notifier)
        .placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    // No order should have been created
    final orders = await h.server.getOrders();
    expect(orders, isEmpty);

    // Cart in controller should now have the updated price
    final cart = h.container.read(cartControllerProvider);
    expect(cart.lines.first.unitPricePaise, p.pricePaise + 2000);
  });

  test('server 409 conflict returns CheckoutNeedsReview and re-reconciles cart',
      () async {
    final p = h.server.products.first;
    await h.container.read(cartControllerProvider.notifier).add(p);

    // Simulate out of stock after reconciler runs by setting stock to 0 directly
    h.server.setStock(p.id, 0);

    final result = await h.container
        .read(checkoutControllerProvider.notifier)
        .placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    expect(h.container.read(cartControllerProvider).isEmpty, isTrue);
  });
}
