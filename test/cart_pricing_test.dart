import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';

CartLine line(String id, int pricePaise, int qty) => CartLine(
      productId: id,
      name: id,
      emoji: '🛒',
      unit: '1 pc',
      unitPricePaise: pricePaise,
      quantity: qty,
      maxPerOrder: 10,
    );

void main() {
  final config = AppConfig.defaults(); // fee ₹25, free delivery from ₹199

  test('empty cart costs nothing', () {
    final pricing = CartPricing.compute(const Cart.empty(), config);
    expect(pricing.totalPaise, 0);
    expect(pricing.deliveryFeePaise, 0);
  });

  test('small cart pays the delivery fee', () {
    final cart = Cart(lines: [line('a', 4000, 2)]); // ₹80
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.subtotalPaise, 8000);
    expect(pricing.deliveryFeePaise, 2500);
    expect(pricing.totalPaise, 10500);
  });

  test('large cart gets free delivery', () {
    final cart = Cart(lines: [line('a', 15000, 2)]); // ₹300
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 30000);
  });

  test('flat coupon is applied when the minimum order is met', () {
    final coupon = Coupon(
      code: 'FLAT50',
      type: CouponType.flat,
      value: 5000,
      minOrderPaise: 29900,
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final cart = Cart(lines: [line('a', 20000, 2)], coupon: coupon); // ₹400
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.discountPaise, 5000);
    expect(pricing.totalPaise, 35000);
  });
}
