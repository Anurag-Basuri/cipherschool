class Category {
  const Category({required this.id, required this.name, required this.emoji});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String? ?? '🛒',
      );

  final String id;
  final String name;
  final String emoji;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'emoji': emoji};
}

/// A sellable product. All money is in paise.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.emoji,
    required this.unit,
    required this.pricePaise,
    required this.mrpPaise,
    required this.stock,
    required this.maxPerOrder,
  });

  final String id;
  final String name;
  final String categoryId;
  final String emoji;
  final String unit;
  final int pricePaise;
  final int mrpPaise;
  final int stock;
  final int maxPerOrder;

  bool get inStock => stock > 0;

  bool get hasDiscount => mrpPaise > pricePaise;

  int get discountPercent =>
      hasDiscount ? ((mrpPaise - pricePaise) * 100 ~/ mrpPaise) : 0;

  /// The most a customer can add to the cart right now.
  int get purchasableQuantity => stock < maxPerOrder ? stock : maxPerOrder;

  /// Local (cache) representation. Uses paise, not the API format.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'name': name,
        'categoryId': categoryId,
        'emoji': emoji,
        'unit': unit,
        'pricePaise': pricePaise,
        'mrpPaise': mrpPaise,
        'stock': stock,
        'maxPerOrder': maxPerOrder,
      };

  factory Product.fromCacheJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        categoryId: json['categoryId'] as String,
        emoji: json['emoji'] as String,
        unit: json['unit'] as String,
        pricePaise: json['pricePaise'] as int,
        mrpPaise: json['mrpPaise'] as int,
        stock: json['stock'] as int,
        maxPerOrder: json['maxPerOrder'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is Product &&
      other.id == id &&
      other.name == name &&
      other.categoryId == categoryId &&
      other.emoji == emoji &&
      other.unit == unit &&
      other.pricePaise == pricePaise &&
      other.mrpPaise == mrpPaise &&
      other.stock == stock &&
      other.maxPerOrder == maxPerOrder;

  @override
  int get hashCode => Object.hash(id, name, categoryId, emoji, unit,
      pricePaise, mrpPaise, stock, maxPerOrder);

  @override
  String toString() => 'Product($id, $name, $pricePaise paise, stock $stock)';
}

/// One page of a paginated product listing.
class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.nextCursor,
    this.fromCache = false,
  });

  final List<Product> items;

  /// Opaque cursor for the next page, or null when this is the last page.
  final String? nextCursor;

  /// True when the page was served from the on-device cache.
  final bool fromCache;

  CatalogPage copyWith({bool? fromCache}) => CatalogPage(
        items: items,
        nextCursor: nextCursor,
        fromCache: fromCache ?? this.fromCache,
      );

  Map<String, dynamic> toCacheJson() => {
        'items': items.map((p) => p.toCacheJson()).toList(),
        'nextCursor': nextCursor,
      };

  factory CatalogPage.fromCacheJson(Map<String, dynamic> json) => CatalogPage(
        items: (json['items'] as List)
            .map((e) => Product.fromCacheJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}
