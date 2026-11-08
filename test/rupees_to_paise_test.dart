// The legacy catalog API sends prices as rupee doubles. Multiplying by 100
// and truncating loses a paisa for values such as 19.99 (1998.9999999999998).
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';
import 'package:quickkart/features/catalog/data/product_dto.dart';

void main() {
  test('converts rupee doubles to exact paise', () {
    expect(rupeesToPaise(19.99), 1999);
    expect(rupeesToPaise(4.35), 435);
    expect(rupeesToPaise(0.29), 29);
    expect(rupeesToPaise(8.2), 820);
  });

  test('whole rupees and integers still work', () {
    expect(rupeesToPaise(54.0), 5400);
    expect(rupeesToPaise(50), 5000);
  });

  test('ProductDto maps a fractional API price without losing a paisa', () {
    final product = ProductDto.fromJson({
      'id': 'x-01',
      'name': 'X',
      'categoryId': 'x',
      'price': 19.99,
      'mrp': 24.35,
      'stock': 5,
      'maxPerOrder': 3,
    });

    expect(product.pricePaise, 1999);
    expect(product.mrpPaise, 2435);
  });
}
