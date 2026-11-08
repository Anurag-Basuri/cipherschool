// BUG-10: ProductSearchController sends 1-character queries to the API
// (which triggers 400 QUERY_TOO_SHORT error) and does not guard against
// stale out-of-order responses overwriting newer searches.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/search/search_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  test('single character query does not hit API and does not produce error',
      () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final controller = h.container.read(searchControllerProvider.notifier);
    await controller.search('a');

    final state = h.container.read(searchControllerProvider);
    expect(state.errorMessage, isNull);
    expect(state.results, isEmpty);
    expect(state.isLoading, isFalse);
    expect(
      h.server.requestLog.where((r) => r.path.contains('/search')),
      isEmpty,
    );
  });

  test('stale slow response does not overwrite newer fast response', () async {
    final h = TestHarness();
    addTearDown(h.dispose);

    final controller = h.container.read(searchControllerProvider.notifier);

    final f1 = controller.search('milk');
    final f2 = controller.search('chips');
    await Future.wait([f1, f2]);

    final state = h.container.read(searchControllerProvider);
    expect(state.query, 'chips');
    expect(
      state.results.every((p) =>
          p.name.toLowerCase().contains('chips') || p.id.contains('chips')),
      isTrue,
    );
  });
}
