// BUG-7: CategoryScreen listens to remoteUpdates in initState without
// cancelling the subscription in dispose(). When config is published after the
// screen is popped, setState() is called on an unmounted state, crashing or leaking.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/domain/product.dart';
import 'package:quickkart/features/catalog/presentation/category_screen.dart';

import 'helpers/test_harness.dart';

void main() {
  testWidgets('CategoryScreen does not call setState after dispose on config update',
      (tester) async {
    final h = TestHarness();
    addTearDown(h.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(
          home: CategoryScreen(
            category: Category(id: 'dairy', name: 'Dairy', emoji: '🥛'),
          ),
        ),
      ),
    );
    await tester.pump();

    // Navigate away / dispose CategoryScreen
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(
          home: SizedBox(),
        ),
      ),
    );
    await tester.pump();

    // Trigger config update while CategoryScreen is disposed
    h.server.publishConfig({'free_delivery_threshold_paise': 29900});

    // Allow any pending async stream callbacks to run
    await tester.pumpAndSettle();

    // Must not have thrown "setState() called after dispose()"
    expect(tester.takeException(), isNull);
  });
}
