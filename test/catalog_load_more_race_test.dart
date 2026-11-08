// BUG-9: Calling loadMore() multiple times concurrently (e.g. on rapid scrolling)
// fetches the same page multiple times and appends duplicate items.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  test('concurrent loadMore calls do not duplicate items', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final controller = h.container
        .read(catalogControllerProvider(kAllProductsCategory).notifier);
    // Allow initial page load to finish
    await Future<void>.delayed(Duration.zero);
    final countAfterFirstPage = h.container
        .read(catalogControllerProvider(kAllProductsCategory))
        .items
        .length;
    expect(countAfterFirstPage, 10);

    // Two rapid loadMore calls before either completes (simulating fast scrolling)
    final f1 = controller.loadMore();
    final f2 = controller.loadMore();
    await Future.wait([f1, f2]);

    final items = h.container
        .read(catalogControllerProvider(kAllProductsCategory))
        .items;
    final ids = items.map((p) => p.id).toList();
    final uniqueIds = ids.toSet();

    // Must not have duplicate items
    expect(ids.length, uniqueIds.length);
  });
}
