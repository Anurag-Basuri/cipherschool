import '../../catalog/domain/product.dart';
import 'coupon.dart';

/// One product line in the cart. [unitPricePaise] is the price the user was
/// shown when they added / last reviewed the item.
class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    required this.emoji,
    required this.unit,
    required this.unitPricePaise,
    required this.quantity,
    required this.maxPerOrder,
  });

  factory CartLine.fromProduct(Product p, {int quantity = 1}) => CartLine(
        productId: p.id,
        name: p.name,
        emoji: p.emoji,
        unit: p.unit,
        unitPricePaise: p.pricePaise,
        quantity: quantity,
        maxPerOrder: p.purchasableQuantity,
      );

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
        productId: json['productId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        unit: json['unit'] as String,
        unitPricePaise: json['unitPricePaise'] as int,
        quantity: json['quantity'] as int,
        maxPerOrder: json['maxPerOrder'] as int,
      );

  final String productId;
  final String name;
  final String emoji;
  final String unit;
  final int unitPricePaise;
  final int quantity;

  /// Upper bound for [quantity] (min of stock and per-order limit at the
  /// time the line was last refreshed).
  final int maxPerOrder;

  int get lineTotalPaise => unitPricePaise * quantity;

  CartLine copyWith({
    String? name,
    int? unitPricePaise,
    int? quantity,
    int? maxPerOrder,
  }) =>
      CartLine(
        productId: productId,
        name: name ?? this.name,
        emoji: emoji,
        unit: unit,
        unitPricePaise: unitPricePaise ?? this.unitPricePaise,
        quantity: quantity ?? this.quantity,
        maxPerOrder: maxPerOrder ?? this.maxPerOrder,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'emoji': emoji,
        'unit': unit,
        'unitPricePaise': unitPricePaise,
        'quantity': quantity,
        'maxPerOrder': maxPerOrder,
      };

  @override
  bool operator ==(Object other) =>
      other is CartLine &&
      other.productId == productId &&
      other.name == name &&
      other.emoji == emoji &&
      other.unit == unit &&
      other.unitPricePaise == unitPricePaise &&
      other.quantity == quantity &&
      other.maxPerOrder == maxPerOrder;

  @override
  int get hashCode => Object.hash(
      productId, name, emoji, unit, unitPricePaise, quantity, maxPerOrder);

  @override
  String toString() =>
      'CartLine($productId x$quantity @ $unitPricePaise, max $maxPerOrder)';
}

/// Immutable cart.
class Cart {
  const Cart({this.lines = const [], this.coupon});

  const Cart.empty()
      : lines = const [],
        coupon = null;

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
        lines: (json['lines'] as List)
            .map((e) => CartLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        coupon: json['coupon'] == null
            ? null
            : Coupon.fromJson(json['coupon'] as Map<String, dynamic>),
      );

  final List<CartLine> lines;
  final Coupon? coupon;

  bool get isEmpty => lines.isEmpty;

  /// Total number of units (shown on the cart badge).
  int get totalQuantity => lines.fold(0, (sum, l) => sum + l.quantity);

  int get subtotalPaise => lines.fold(0, (sum, l) => sum + l.lineTotalPaise);

  CartLine? lineFor(String productId) {
    for (final l in lines) {
      if (l.productId == productId) return l;
    }
    return null;
  }

  int quantityOf(String productId) => lineFor(productId)?.quantity ?? 0;

  /// Adds [line] or replaces the existing line for the same product.
  Cart upsertLine(CartLine line) {
    final exists = lineFor(line.productId) != null;
    return Cart(
      lines: exists
          ? [
              for (final l in lines)
                if (l.productId == line.productId) line else l
            ]
          : [...lines, line],
      coupon: coupon,
    );
  }

  /// Sets the quantity of a line. A quantity <= 0 removes the line.
  Cart updateQuantity(String productId, int quantity) {
    final line = lineFor(productId);
    if (line == null) return this;
    if (quantity <= 0) return removeLine(productId);
    return upsertLine(line.copyWith(quantity: quantity));
  }

  Cart removeLine(String productId) => Cart(
        lines: lines.where((l) => l.productId != productId).toList(),
        coupon: coupon,
      );

  Cart withCoupon(Coupon coupon) => Cart(lines: lines, coupon: coupon);

  Cart withoutCoupon() => Cart(lines: lines);

  Map<String, dynamic> toJson() => {
        'lines': lines.map((l) => l.toJson()).toList(),
        'coupon': coupon?.toJson(),
      };

  @override
  bool operator ==(Object other) {
    if (other is! Cart || other.coupon != coupon) return false;
    if (other.lines.length != lines.length) return false;
    for (var i = 0; i < lines.length; i++) {
      if (other.lines[i] != lines[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(lines), coupon);

  @override
  String toString() => 'Cart($lines, coupon: ${coupon?.code})';
}
