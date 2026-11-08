// BUSINESS_RULES.md section 2: orders of Rs 199 OR MORE get free delivery,
// measured after the coupon discount.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';

CartLine line(int pricePaise, int qty) => CartLine(
      productId: 'p',
      name: 'p',
      emoji: '🛒',
      unit: '1 pc',
      unitPricePaise: pricePaise,
      quantity: qty,
      maxPerOrder: 10,
    );

void main() {
  final config = AppConfig.defaults(); // fee 2500, free from 19900

  test('an order of exactly the threshold gets free delivery', () {
    final pricing = CartPricing.compute(Cart(lines: [line(19900, 1)]), config);

    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 19900);
    expect(pricing.amountForFreeDeliveryPaise, 0);
  });

  test('one paisa below the threshold still pays the fee', () {
    final pricing = CartPricing.compute(Cart(lines: [line(19899, 1)]), config);

    expect(pricing.deliveryFeePaise, 2500);
    expect(pricing.amountForFreeDeliveryPaise, 1);
  });

  test('the threshold applies to the amount after the coupon', () {
    final coupon = Coupon(
      code: 'FLAT50',
      type: CouponType.flat,
      value: 5000,
      minOrderPaise: 0,
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    // 24900 - 5000 = 19900 -> exactly the threshold -> free delivery.
    final cart = Cart(lines: [line(24900, 1)], coupon: coupon);

    final pricing = CartPricing.compute(cart, config);

    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 19900);
  });
}
