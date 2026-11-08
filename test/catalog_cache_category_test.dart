// BUG-8: CatalogRepository uses cacheKey 'page.${cursor ?? 'first'}' without
// categoryId. Browsing one category offline returns products from another category.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  test('offline cache keeps separate pages for different categories', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final repo = h.container.read(catalogRepositoryProvider);

    // 1. Fetch dairy online (stores into cache)
    final dairyPage = await repo.getPage(categoryId: 'dairy');
    expect(dairyPage.items.every((p) => p.categoryId == 'dairy'), isTrue);

    // 2. Fetch snacks online
    final snacksPage = await repo.getPage(categoryId: 'snacks');
    expect(snacksPage.items.every((p) => p.categoryId == 'snacks'), isTrue);

    // 3. Go offline
    h.server.chaos.offline = true;

    // 4. Read dairy offline
    final offlineDairy = await repo.getPage(categoryId: 'dairy');
    expect(offlineDairy.fromCache, isTrue);
    expect(offlineDairy.items.every((p) => p.categoryId == 'dairy'), isTrue);
  });
}
