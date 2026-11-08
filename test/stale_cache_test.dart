// QK-102: Prices don't update on pull-to-refresh, placed orders don't show
// on My Orders page, and published config doesn't update until app restart
// due to ApiClient's 10-minute GET cache and non-invalidated ordersProvider.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_client.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  test('pull to refresh fetches updated prices instead of cached ones',
      () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    // Initial page load
    final controller =
        h.container.read(catalogControllerProvider('dairy').notifier);
    // Allow microtask to complete
    await Future<void>.delayed(Duration.zero);
    final initialItems =
        h.container.read(catalogControllerProvider('dairy')).items;
    expect(initialItems, isNotEmpty);
    final first = initialItems.first;
    final initialPrice = first.pricePaise;

    // Server price changes
    h.server.setPrice(first.id, initialPrice + 1000);

    // Pull to refresh
    await controller.refresh();

    final refreshedItems =
        h.container.read(catalogControllerProvider('dairy')).items;
    final refreshedFirst = refreshedItems.firstWhere((p) => p.id == first.id);
    expect(refreshedFirst.pricePaise, initialPrice + 1000);
  });

  test('ordersProvider updates after order is placed', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    // Initial orders list is empty
    final initialOrders = await h.container.read(ordersProvider.future);
    expect(initialOrders, isEmpty);

    // Add item and place order
    final cart = h.container.read(cartControllerProvider.notifier);
    await cart.add(h.server.products.first);

    final result =
        await h.container.read(checkoutControllerProvider.notifier).placeOrder();
    expect(result, isA<CheckoutSuccess>());

    // Orders list should immediately show the placed order
    final updatedOrders = await h.container.read(ordersProvider.future);
    expect(updatedOrders.length, 1);
  });

  test('ConfigRepository.load fetches fresh config after update', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final configRepo = h.container.read(configRepositoryProvider);
    final c1 = await configRepo.load();
    expect(c1.storeOpen, isTrue);

    // Close store on server
    h.server.publishConfig({'store_open': false});

    final c2 = await configRepo.load();
    expect(c2.storeOpen, isFalse);
  });

  test('ApiClient does not retry non-transient 4xx errors', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final client = h.container.read(apiClientProvider);

    // 400 INVALID_CURSOR
    await expectLater(
      () => client.get('/v1/products', query: {'cursor': 'invalid'}),
      throwsA(isA<ClientException>()),
    );
    // Request should only be sent once, not retried 2 more times
    final count =
        h.server.requestLog.where((r) => r.path == '/v1/products').length;
    expect(count, 1);
  });
}
