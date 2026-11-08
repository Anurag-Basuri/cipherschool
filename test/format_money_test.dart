// BUSINESS_RULES.md section 1: prices are shown in rupees, with paise only
// when there are any: Rs 50, Rs 49.99.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  test('whole rupees are shown without paise', () {
    expect(formatMoney(5000), '₹50');
    expect(formatMoney(0), '₹0');
  });

  test('paise are shown when present', () {
    expect(formatMoney(4999), '₹49.99');
  });

  test('single-digit paise are zero padded', () {
    expect(formatMoney(4905), '₹49.05');
  });

  test('amounts under one rupee keep their paise', () {
    expect(formatMoney(50), '₹0.50');
  });
}
