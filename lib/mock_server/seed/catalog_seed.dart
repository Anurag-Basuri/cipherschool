// Seed catalog for the mock server.
//
// Row format: emoji|name|unit|price|mrp|stock|maxPerOrder
// Prices are rupees written as decimal strings; they are parsed exactly
// (no floating point) by the mock server.

class SeedCategory {
  const SeedCategory(this.id, this.name, this.emoji, this.rows);

  final String id;
  final String name;
  final String emoji;
  final List<String> rows;
}

class SeedCatalog {
  const SeedCatalog({
    required this.storeName,
    required this.categories,
    required this.legacyProductIds,
  });

  final String storeName;
  final List<SeedCategory> categories;

  /// Products still served by the older catalog service.
  final Set<String> legacyProductIds;
}

/// Product ids are `<categoryId>-<2 digit index>`, e.g. `dairy-03`.
String seedProductId(String categoryId, int index) =>
    '$categoryId-${index.toString().padLeft(2, '0')}';

SeedCatalog seedCatalogFor(String variant) => _variantA;

// ---------------------------------------------------------------------------
// Variant A - Grocery
// ---------------------------------------------------------------------------
const _variantA = SeedCatalog(
  storeName: 'QuickKart Grocery',
  legacyProductIds: {'dairy-00', 'dairy-02', 'snacks-09'},
  categories: [
    SeedCategory('fruits', 'Fruits & Veggies', '🥦', [
      '🍎|Shimla Apple|4 pcs (approx 500 g)|129|159|40|6',
      '🍌|Robusta Banana|6 pcs|49|59|60|6',
      '🥭|Alphonso Mango|2 pcs|199|249|8|4',
      '🍅|Hybrid Tomato|500 g|19.99|29|80|5',
      '🧅|Onion|1 kg|45|55|90|5',
      '🥔|Potato|1 kg|39|45|90|5',
      '🥕|Ooty Carrot|500 g|35|35|30|5',
      '🥒|Cucumber|500 g|29|35|25|5',
      '🍋|Lemon|4 pcs|25|30|50|5',
      '🍇|Green Grapes|500 g|79.99|99|12|4',
      '🌶️|Green Chilli|100 g|12|15|40|5',
      '🍉|Watermelon|1 pc (approx 2 kg)|89|99|3|2',
    ]),
    SeedCategory('dairy', 'Dairy, Bread & Eggs', '🥛', [
      '🥛|Toned Milk|500 ml|29|29|120|6',
      '🧈|Salted Butter|100 g|58|62|30|4',
      '🧀|Cheese Slices|200 g|149|160|18|4',
      '🥚|Farm Eggs|6 pcs|54|60|45|4',
      '🍞|Brown Bread|400 g|50|55|25|4',
      '🥣|Curd Cup|400 g|35|40|40|5',
      '🍦|Paneer|200 g|89|95|20|4',
      '🥛|Lassi Sweet|200 ml|20|20|60|8',
      '🧁|Pav|6 pcs|30|35|30|4',
      '🥛|Double Toned Milk|1 L|54|56|0|6',
      '🍮|Mishti Doi|100 g|25|30|15|6',
      '🥞|Instant Dosa Batter|1 kg|74.99|90|10|3',
    ]),
    SeedCategory('snacks', 'Snacks & Munchies', '🍿', [
      '🥔|Classic Salted Chips|52 g|20|20|100|10',
      '🍿|Butter Popcorn|90 g|45|50|35|5',
      '🥜|Roasted Peanuts|200 g|69.99|80|25|5',
      '🍪|Chocolate Chip Cookies|150 g|40|45|50|6',
      '🍫|Milk Chocolate Bar|50 g|50|50|70|6',
      '🥨|Masala Namkeen|200 g|55|60|40|5',
      '🍘|Rice Crackers|100 g|35|40|20|5',
      '🧆|Bhujia Sev|400 g|105|120|30|4',
      '🍬|Kaju Katli|250 g|299|349|6|2',
      '🥮|Soan Papdi|500 g|149|180|2|2',
      '🍩|Mini Donuts|4 pcs|99|120|12|3',
      '🌰|Premium Cashews|200 g|249|299|15|3',
    ]),
    SeedCategory('beverages', 'Cold Drinks & Juices', '🥤', [
      '🥤|Cola Can|300 ml|40|40|80|10',
      '🧃|Mixed Fruit Juice|1 L|110|125|30|4',
      '💧|Mineral Water|1 L|20|20|150|12',
      '🧋|Cold Coffee|180 ml|35|40|40|6',
      '🍵|Green Tea Bags|25 pcs|160|175|20|3',
      '☕|Instant Coffee|50 g|179|190|25|3',
      '🥥|Tender Coconut Water|200 ml|45|50|35|6',
      '🍋|Lemon Soda|300 ml|25|25|60|8',
      '🥤|Energy Drink|250 ml|125|125|25|4',
      '🫖|Masala Chai Premix|10 sachets|17.99|20|40|6',
      '🧉|Iced Tea Peach|300 ml|50|60|0|6',
      '🥛|Rose Milk|200 ml|30|30|45|6',
    ]),
    SeedCategory('household', 'Home & Cleaning', '🧽', [
      '🧼|Dishwash Bar|3 x 200 g|60|66|50|4',
      '🧴|Liquid Detergent|1 L|209|240|20|3',
      '🧻|Toilet Roll|4 rolls|160|180|30|3',
      '🧽|Scrub Sponge|3 pcs|45|55|40|4',
      '🪣|Floor Cleaner|1 L|199|215|25|3',
      '🗑️|Garbage Bags|30 pcs|99|110|35|3',
      '🕯️|Diya Candles|12 pcs|79.99|99|18|4',
      '🪔|Clay Diyas|6 pcs|60|75|5|4',
      '🧹|Broom|1 pc|129|149|10|2',
      '🧯|Toilet Cleaner|500 ml|92|99|28|3',
      '🔋|AA Batteries|4 pcs|120|130|20|3',
      '💡|LED Bulb 9W|1 pc|99|149|15|3',
    ]),
  ],
);
