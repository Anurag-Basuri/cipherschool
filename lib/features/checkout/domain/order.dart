enum OrderStatus { placed, packed, outForDelivery, delivered, unknown }

OrderStatus orderStatusFromApi(String? s) {
  switch (s) {
    case 'placed':
      return OrderStatus.placed;
    case 'packed':
      return OrderStatus.packed;
    case 'out_for_delivery':
      return OrderStatus.outForDelivery;
    case 'delivered':
      return OrderStatus.delivered;
    default:
      return OrderStatus.unknown;
  }
}

extension OrderStatusLabel on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.placed:
        return 'Order placed';
      case OrderStatus.packed:
        return 'Packed';
      case OrderStatus.outForDelivery:
        return 'Out for delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.unknown:
        return 'Updating…';
    }
  }
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.emoji,
    required this.quantity,
    required this.unitPricePaise,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        productId: json['productId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String? ?? '🛒',
        quantity: json['quantity'] as int,
        unitPricePaise: json['unitPricePaise'] as int,
      );

  final String productId;
  final String name;
  final String emoji;
  final int quantity;
  final int unitPricePaise;
}

class Order {
  const Order({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.deliveryFeePaise,
    required this.totalPaise,
    this.couponCode,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        status: orderStatusFromApi(json['status'] as String?),
        createdAt: DateTime.parse(json['createdAt'] as String),
        items: (json['items'] as List)
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtotalPaise: json['subtotalPaise'] as int,
        discountPaise: json['discountPaise'] as int,
        deliveryFeePaise: json['deliveryFeePaise'] as int,
        totalPaise: json['totalPaise'] as int,
        couponCode: json['couponCode'] as String?,
      );

  final String id;
  final OrderStatus status;
  final DateTime createdAt;
  final List<OrderItem> items;
  final int subtotalPaise;
  final int discountPaise;
  final int deliveryFeePaise;
  final int totalPaise;
  final String? couponCode;

  int get itemCount => items.fold(0, (s, i) => s + i.quantity);
}
