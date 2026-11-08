// Two quick taps on "+" must add two units. The controller used to read the
// cart, await the disk write, and only then publish the new state, so the
// second tap was computed from the stale cart and one increment was lost.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
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

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('two rapid increments add two units', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(product('milk')); // 1

    // No await between the taps, like a fast double tap on "+".
    final first = cart.increment('milk');
    final second = cart.increment('milk');
    await Future.wait([first, second]);

    expect(h.read(cartControllerProvider).quantityOf('milk'), 3);
  });

  test('rapid "+" then "-" ends at the right quantity', () async {
    final cart = h.read(cartControllerProvider.notifier);
    await cart.add(product('milk')); // 1

    final inc = cart.increment('milk'); // 2
    final dec = cart.decrement('milk'); // back to 1
    await Future.wait([inc, dec]);

    expect(h.read(cartControllerProvider).quantityOf('milk'), 1);
  });
}
