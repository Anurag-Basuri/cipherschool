// In-process mock backend.
//
// This file simulates the QuickKart backend (REST API + realtime database +
// remote config + push notifications) so the assignment runs without any
// server. Treat it as a black box owned by the "backend team":
//
//   * DO NOT change its behaviour to make your app work.
//   * You MAY read it to understand the API, and use its admin methods
//     (setPrice, setStock, publishConfig, ...) in your tests.
//
// Its data is persisted on the device so it survives app restarts, exactly
// like a real server would.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../core/network/transport.dart';
import '../core/storage/key_value_store.dart';
import 'chaos_settings.dart';
import 'seed/catalog_seed.dart';
import 'seed/variant.dart';

class MockServer {
  MockServer._({
    required this.variant,
    required KeyValueStore? store,
    required this.chaos,
    required Random random,
    required DateTime Function() clock,
    this.realtimeTick = const Duration(milliseconds: 500),
  })  : _store = store,
        _random = random,
        _clock = clock {
    transport = _MockTransport(this);
  }

  /// Opens (or seeds) the persisted server database.
  static Future<MockServer> open(
    KeyValueStore store, {
    String variant = kAssignmentVariant,
    ChaosSettings? chaos,
  }) async {
    final server = MockServer._(
      variant: variant,
      store: store,
      chaos: chaos ?? ChaosSettings.realistic(),
      random: Random(),
      clock: DateTime.now,
    );
    final raw = await store.getString(server._dbKey);
    if (raw == null) {
      server._seed();
      await server._persist();
    } else {
      try {
        server._restore(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        server._seed();
        await server._persist();
      }
    }
    return server;
  }

  /// Non persistent server for tests. Defaults to a perfect network.
  factory MockServer.inMemory({
    String variant = 'A',
    ChaosSettings? chaos,
    Random? random,
    DateTime Function()? clock,
    Duration realtimeTick = const Duration(milliseconds: 100),
  }) {
    final server = MockServer._(
      variant: variant,
      store: null,
      chaos: chaos ?? ChaosSettings.none(),
      random: random ?? Random(42),
      clock: clock ?? DateTime.now,
      realtimeTick: realtimeTick,
    );
    server._seed();
    return server;
  }

  final String variant;
  final ChaosSettings chaos;
  final Duration realtimeTick;
  final KeyValueStore? _store;
  final Random _random;
  final DateTime Function() _clock;

  late final Transport transport;

  /// Every request that reached the transport (including failed ones).
  final List<TransportRequest> requestLog = [];

  String get _dbKey => '__mock_server_db_v1_$variant';

  // ------------------------------------------------------------------ data
  late String storeName;
  final List<_Category> _categories = [];
  final List<_Product> _products = [];
  final Map<String, _Coupon> _coupons = {};
  final List<_Order> _orders = [];
  final Map<String, _IdempotencyRecord> _idempotency = {};
  final Map<String, Object?> _config = {};
  int _configVersion = 1;
  int _nextOrderNumber = 1001;
  DateTime? _lastPriceDrift;

  // ------------------------------------------------------------- realtime
  final StreamController<int> _configCtrl = StreamController<int>.broadcast();
  int _configListeners = 0;
  final StreamController<Map<String, dynamic>> _pushCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  int _pushListeners = 0;
  Timer? _pushTimer;
  final Map<String, String> _lastPushedStatus = {};

  // ===================================================================
  // Seeding & persistence
  // ===================================================================

  void _seed() {
    final seed = seedCatalogFor(variant);
    storeName = seed.storeName;
    _categories.clear();
    _products.clear();
    for (final c in seed.categories) {
      _categories.add(_Category(c.id, c.name, c.emoji));
      for (var i = 0; i < c.rows.length; i++) {
        final parts = c.rows[i].split('|');
        final id = seedProductId(c.id, i);
        _products.add(_Product(
          id: id,
          categoryId: c.id,
          emoji: parts[0],
          name: parts[1],
          unit: parts[2],
          pricePaise: _parseRupees(parts[3]),
          mrpPaise: _parseRupees(parts[4]),
          stock: int.parse(parts[5]),
          maxPerOrder: int.parse(parts[6]),
          active: true,
          legacy: seed.legacyProductIds.contains(id),
        ));
      }
    }
    final now = _clock().toUtc();
    _coupons
      ..clear()
      ..addAll({
        'FLAT50': _Coupon('FLAT50', 'flat', 5000, null, 29900,
            now.add(const Duration(days: 30)), '₹50 off on orders above ₹299'),
        'SAVE10': _Coupon('SAVE10', 'percent', 10, 7500, 19900,
            now.add(const Duration(days: 30)), '10% off up to ₹75, min ₹199'),
        'DIWALI100': _Coupon('DIWALI100', 'flat', 10000, null, 49900,
            now.add(const Duration(days: 7)), '₹100 off on orders above ₹499'),
        'WELCOME100': _Coupon('WELCOME100', 'flat', 10000, null, 0,
            now.subtract(const Duration(days: 2)), '₹100 off (expired)'),
      });
    _orders.clear();
    _idempotency.clear();
    _config
      ..clear()
      ..addAll(_defaultConfig());
    _configVersion = 1;
    _nextOrderNumber = 1001;
    _lastPriceDrift = _clock();
  }

  static Map<String, Object?> _defaultConfig() => {
        'min_supported_version': '1.0.0',
        'latest_version': '1.4.0',
        'update_url': 'https://example.com/quickkart/download',
        'store_open': true,
        'store_closed_message':
            'We are closed for a short break. Back in 30 minutes!',
        'home_banner': jsonEncode({
          'title': 'Diwali Dhamaka',
          'subtitle': 'Up to 40% off on sweets, snacks & diyas',
          'color': '#FF6F00',
        }),
        'home_sections': jsonEncode(
            ['banner', 'categories', 'deals', 'all_products']),
        'delivery_fee_paise': 2500,
        'free_delivery_threshold_paise': 19900,
      };

  static int _parseRupees(String s) {
    final parts = s.split('.');
    final rupees = int.parse(parts[0]);
    if (parts.length == 1) return rupees * 100;
    final frac = parts[1].padRight(2, '0').substring(0, 2);
    return rupees * 100 + int.parse(frac);
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    await store.setString(_dbKey, jsonEncode(_toDb()));
  }

  void _persistSoon() {
    unawaited(_persist());
  }

  Map<String, dynamic> _toDb() => {
        'storeName': storeName,
        'categories': _categories.map((c) => c.toDb()).toList(),
        'products': _products.map((p) => p.toDb()).toList(),
        'coupons': _coupons.values.map((c) => c.toDb()).toList(),
        'orders': _orders.map((o) => o.toDb()).toList(),
        'idempotency':
            _idempotency.map((k, v) => MapEntry(k, v.toDb())),
        'config': _config,
        'configVersion': _configVersion,
        'nextOrderNumber': _nextOrderNumber,
      };

  void _restore(Map<String, dynamic> db) {
    storeName = db['storeName'] as String;
    _categories
      ..clear()
      ..addAll((db['categories'] as List)
          .map((e) => _Category.fromDb(e as Map<String, dynamic>)));
    _products
      ..clear()
      ..addAll((db['products'] as List)
          .map((e) => _Product.fromDb(e as Map<String, dynamic>)));
    _coupons
      ..clear()
      ..addEntries((db['coupons'] as List).map((e) {
        final c = _Coupon.fromDb(e as Map<String, dynamic>);
        return MapEntry(c.code, c);
      }));
    _orders
      ..clear()
      ..addAll((db['orders'] as List)
          .map((e) => _Order.fromDb(e as Map<String, dynamic>)));
    _idempotency
      ..clear()
      ..addAll((db['idempotency'] as Map<String, dynamic>).map((k, v) =>
          MapEntry(k, _IdempotencyRecord.fromDb(v as Map<String, dynamic>))));
    _config
      ..clear()
      ..addAll(db['config'] as Map<String, dynamic>);
    _configVersion = db['configVersion'] as int;
    _nextOrderNumber = db['nextOrderNumber'] as int;
    _lastPriceDrift = _clock();
  }

  // ===================================================================
  // Admin API (used by Dev Tools and by tests)
  // ===================================================================

  List<String> get productIds => _products.map((p) => p.id).toList();

  /// Current server-side state of a product (prices in paise).
  ServerProductSnapshot product(String id) {
    final p = _productById(id);
    if (p == null) throw ArgumentError('Unknown product $id');
    return ServerProductSnapshot(
      id: p.id,
      name: p.name,
      categoryId: p.categoryId,
      pricePaise: p.pricePaise,
      mrpPaise: p.mrpPaise,
      stock: p.stock,
      maxPerOrder: p.maxPerOrder,
      active: p.active,
    );
  }

  void setPrice(String productId, int pricePaise) {
    final p = _requireProduct(productId);
    p.pricePaise = pricePaise;
    if (p.mrpPaise < pricePaise) p.mrpPaise = pricePaise;
    _persistSoon();
  }

  void setStock(String productId, int stock) {
    _requireProduct(productId).stock = max(0, stock);
    _persistSoon();
  }

  void setMaxPerOrder(String productId, int maxPerOrder) {
    _requireProduct(productId).maxPerOrder = max(1, maxPerOrder);
    _persistSoon();
  }

  /// Inactive products are no longer sold: they disappear from listings and
  /// are reported as `missing` by the batch endpoint.
  void setActive(String productId, bool active) {
    _requireProduct(productId).active = active;
    _persistSoon();
  }

  void expireCoupon(String code) {
    final c = _coupons[code];
    if (c == null) throw ArgumentError('Unknown coupon $code');
    c.expiresAt = _clock().toUtc().subtract(const Duration(minutes: 1));
    _persistSoon();
  }

  /// Simulates a "Remote Config publish" from the console.
  void publishConfig(Map<String, Object?> changes) {
    _config.addAll(changes);
    _configVersion++;
    _persistSoon();
    _configCtrl.add(_configVersion);
  }

  Map<String, Object?> get configValues => Map.unmodifiable(_config);
  int get configVersion => _configVersion;

  /// Number of active listeners on [configUpdates]. Useful to detect leaks.
  int get configListenerCount => _configListeners;

  /// All orders, newest first, in API JSON format.
  List<Map<String, dynamic>> get orders =>
      _orders.reversed.map(_orderJson).toList();

  int get orderCount => _orders.length;

  /// Moves an order to its next status immediately.
  void advanceOrder(String orderId) {
    final o = _orders.firstWhere((o) => o.id == orderId,
        orElse: () => throw ArgumentError('Unknown order $orderId'));
    final elapsed = _elapsedSeconds(o);
    for (final threshold in _statusThresholds.values) {
      if (threshold > elapsed) {
        o.bonusSeconds += threshold - elapsed;
        break;
      }
    }
    _persistSoon();
  }

  /// Creates a realistic set of conflicts for the given cart products:
  /// 1st product: price +15%, 2nd: out of stock, 3rd: only 1 left,
  /// 4th: no longer sold. Also expires [couponCode] if given.
  void simulateCartConflicts(List<String> productIds, {String? couponCode}) {
    for (var i = 0; i < productIds.length; i++) {
      final p = _productById(productIds[i]);
      if (p == null) continue;
      switch (i % 4) {
        case 0:
          setPrice(p.id, ((p.pricePaise * 1.15) ~/ 100) * 100 + 100);
        case 1:
          setStock(p.id, 0);
        case 2:
          setStock(p.id, 1);
        case 3:
          setActive(p.id, false);
      }
    }
    if (couponCode != null && _coupons.containsKey(couponCode)) {
      expireCoupon(couponCode);
    }
  }

  Future<void> resetData() async {
    _seed();
    requestLog.clear();
    await _persist();
    _configCtrl.add(_configVersion);
  }

  Future<void> close() async {
    _pushTimer?.cancel();
    await _configCtrl.close();
    await _pushCtrl.close();
  }

  // ===================================================================
  // Realtime APIs (simulate Firebase Remote Config listener, Firestore
  // document listener and FCM foreground messages)
  // ===================================================================

  /// Emits the new config version whenever config is published.
  Stream<int> get configUpdates => Stream<int>.multi((controller) {
        _configListeners++;
        final sub = _configCtrl.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = () {
          _configListeners--;
          return sub.cancel();
        };
      });

  /// Realtime listener for one order document (like a Firestore snapshot
  /// listener). Emits the current order immediately and then on every change.
  Stream<Map<String, dynamic>> watchOrder(String orderId) {
    Timer? timer;
    String? lastStatus;
    late StreamController<Map<String, dynamic>> controller;

    void emit() {
      final o = _orders.where((o) => o.id == orderId).firstOrNullItem;
      if (o == null) {
        controller.addError(StateError('Order $orderId not found'));
        return;
      }
      final status = _statusOf(o);
      if (status != lastStatus) {
        lastStatus = status;
        controller.add(_orderJson(o));
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        emit();
        timer = Timer.periodic(realtimeTick, (_) => emit());
      },
      onCancel: () {
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  /// Simulated FCM messages (foreground). Payload:
  /// `{title, body, data: {type: 'order_status', orderId, status}}`.
  Stream<Map<String, dynamic>> get pushMessages =>
      Stream<Map<String, dynamic>>.multi((controller) {
        _pushListeners++;
        _ensurePushTimer();
        final sub = _pushCtrl.stream.listen(controller.add,
            onError: controller.addError, onDone: controller.close);
        controller.onCancel = () {
          _pushListeners--;
          if (_pushListeners == 0) {
            _pushTimer?.cancel();
            _pushTimer = null;
          }
          return sub.cancel();
        };
      });

  void _ensurePushTimer() {
    if (_pushTimer != null) return;
    for (final o in _orders) {
      _lastPushedStatus[o.id] = _statusOf(o);
    }
    _pushTimer = Timer.periodic(realtimeTick, (_) {
      for (final o in _orders) {
        final status = _statusOf(o);
        final previous = _lastPushedStatus[o.id];
        if (previous != status) {
          _lastPushedStatus[o.id] = status;
          if (previous == null) continue; // newly placed, no push
          _pushCtrl.add({
            'title': 'Order ${o.id}',
            'body': _statusMessages[status] ?? 'Status: $status',
            'data': {
              'type': 'order_status',
              'orderId': o.id,
              'status': status,
            },
          });
        }
      }
    });
  }

  // ===================================================================
  // HTTP routing
  // ===================================================================

  TransportResponse _handle(TransportRequest req) {
    final segments =
        req.path.split('/').where((s) => s.isNotEmpty).toList();
    Map<String, dynamic> body() {
      final raw = req.body;
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    }

    try {
      if (segments.length < 2 || segments[0] != 'v1') {
        return _error(404, 'NOT_FOUND', 'Unknown endpoint ${req.path}');
      }
      final resource = segments[1];
      switch ((req.method, resource, segments.length)) {
        case ('GET', 'categories', 2):
          return _ok(_categories.map((c) => c.toJson()).toList());
        case ('GET', 'products', 2):
          return _listProducts(req.query);
        case ('GET', 'products', 3) when segments[2] == 'search':
          return _search(req.query['q'] ?? '');
        case ('POST', 'products', 3) when segments[2] == 'batch':
          return _batch(body());
        case ('POST', 'coupons', 3) when segments[2] == 'validate':
          return _validateCoupon(body());
        case ('GET', 'orders', 2):
          return _ok({'items': _orders.reversed.map(_orderJson).toList()});
        case ('GET', 'orders', 3):
          {
            final o =
                _orders.where((o) => o.id == segments[2]).firstOrNullItem;
            if (o == null) {
              return _error(404, 'ORDER_NOT_FOUND', 'Order not found');
            }
            return _ok(_orderJson(o));
          }
        case ('POST', 'orders', 2):
          return _placeOrder(req, body());
        case ('GET', 'config', 2):
          return _ok({'version': _configVersion, 'values': _config});
        default:
          return _error(404, 'NOT_FOUND', 'Unknown endpoint ${req.path}');
      }
    } on FormatException catch (e) {
      return _error(400, 'INVALID_REQUEST', e.message);
    } on TypeError {
      return _error(400, 'INVALID_REQUEST', 'Malformed request body');
    }
  }

  TransportResponse _listProducts(Map<String, String> query) {
    _maybeDriftPrice();
    final categoryId = query['category'];
    final dealsOnly = query['deals'] == 'true';
    final limit = (int.tryParse(query['limit'] ?? '') ?? 10).clamp(1, 30).toInt();
    var offset = 0;
    final cursor = query['cursor'];
    if (cursor != null && cursor.isNotEmpty) {
      try {
        final decoded = utf8.decode(base64Url.decode(cursor));
        offset = int.parse(decoded.split(':').last);
      } catch (_) {
        return _error(400, 'INVALID_CURSOR', 'Cursor is invalid');
      }
    }
    final matching = _products.where((p) {
      if (!p.active) return false;
      if (categoryId != null && categoryId.isNotEmpty) {
        if (p.categoryId != categoryId) return false;
      }
      if (dealsOnly && !(p.mrpPaise > p.pricePaise && p.stock > 0)) {
        return false;
      }
      return true;
    }).toList();
    final page = matching.skip(offset).take(limit).toList();
    final nextOffset = offset + page.length;
    final nextCursor = nextOffset < matching.length
        ? base64Url.encode(utf8.encode('o:$nextOffset'))
        : null;
    return _ok({
      'items': page.map(_productJson).toList(),
      'nextCursor': nextCursor,
    });
  }

  TransportResponse _search(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.length < 2) {
      return _error(400, 'QUERY_TOO_SHORT',
          'Search query must have at least 2 characters');
    }
    final items = _products
        .where((p) => p.active && p.name.toLowerCase().contains(q))
        .take(20)
        .map(_productJson)
        .toList();
    return _ok({'query': rawQuery, 'items': items});
  }

  TransportResponse _batch(Map<String, dynamic> body) {
    final ids = (body['ids'] as List?)?.cast<String>();
    if (ids == null) {
      return _error(400, 'INVALID_REQUEST', '`ids` is required');
    }
    if (ids.length > 50) {
      return _error(400, 'TOO_MANY_IDS', 'At most 50 ids per request');
    }
    final items = <Map<String, dynamic>>[];
    final missing = <String>[];
    for (final id in ids) {
      final p = _productById(id);
      if (p == null || !p.active) {
        missing.add(id);
      } else {
        items.add(_productJson(p));
      }
    }
    return _ok({'items': items, 'missing': missing});
  }

  TransportResponse _validateCoupon(Map<String, dynamic> body) {
    final code = (body['code'] as String? ?? '').trim().toUpperCase();
    final c = _coupons[code];
    if (c == null) {
      return _error(404, 'COUPON_NOT_FOUND', 'This coupon does not exist');
    }
    if (!c.expiresAt.isAfter(_clock().toUtc())) {
      return _error(409, 'COUPON_EXPIRED', 'This coupon has expired');
    }
    return _ok(c.toJson());
  }

  TransportResponse _placeOrder(TransportRequest req, Map<String, dynamic> b) {
    if (_config['store_open'] == false) {
      return _error(503, 'STORE_CLOSED',
          (_config['store_closed_message'] as String?) ?? 'Store is closed');
    }

    final idempotencyKey = req.headers.entries
        .where((e) => e.key.toLowerCase() == 'idempotency-key')
        .map((e) => e.value)
        .firstOrNullItem;
    final fingerprint = jsonEncode(b);
    if (idempotencyKey != null) {
      final existing = _idempotency[idempotencyKey];
      if (existing != null) {
        if (existing.fingerprint != fingerprint) {
          return _error(422, 'IDEMPOTENCY_KEY_REUSED',
              'Idempotency-Key was already used with a different payload');
        }
        final o = _orders.firstWhere((o) => o.id == existing.orderId);
        return _ok(_orderJson(o), status: 200);
      }
    }

    final rawItems = b['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return _error(400, 'EMPTY_CART', 'Order must contain items');
    }
    final lines = <({_Product product, int quantity, int unitPricePaise})>[];
    final unavailable = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      final m = raw as Map<String, dynamic>;
      final id = m['productId'] as String?;
      final qty = m['quantity'];
      final price = m['unitPricePaise'];
      if (id == null || qty is! int || price is! int || qty <= 0) {
        return _error(400, 'INVALID_REQUEST',
            'Each item needs productId, quantity (>0) and unitPricePaise');
      }
      final p = _productById(id);
      if (p == null || !p.active) {
        unavailable.add({'productId': id});
        continue;
      }
      lines.add((product: p, quantity: qty, unitPricePaise: price));
    }
    if (unavailable.isNotEmpty) {
      return _error(409, 'PRODUCT_UNAVAILABLE',
          'Some products are no longer available',
          details: unavailable);
    }

    final priceChanged = [
      for (final l in lines)
        if (l.unitPricePaise != l.product.pricePaise)
          {
            'productId': l.product.id,
            'expectedPricePaise': l.unitPricePaise,
            'currentPricePaise': l.product.pricePaise,
          }
    ];
    if (priceChanged.isNotEmpty) {
      return _error(409, 'PRICE_CHANGED', 'Prices have changed',
          details: priceChanged);
    }

    final overLimit = [
      for (final l in lines)
        if (l.quantity > l.product.maxPerOrder)
          {
            'productId': l.product.id,
            'requested': l.quantity,
            'maxPerOrder': l.product.maxPerOrder,
          }
    ];
    if (overLimit.isNotEmpty) {
      return _error(422, 'QUANTITY_LIMIT', 'Quantity limit exceeded',
          details: overLimit);
    }

    final insufficient = [
      for (final l in lines)
        if (l.quantity > l.product.stock)
          {
            'productId': l.product.id,
            'requested': l.quantity,
            'available': l.product.stock,
          }
    ];
    if (insufficient.isNotEmpty) {
      return _error(409, 'INSUFFICIENT_STOCK', 'Not enough stock',
          details: insufficient);
    }

    final subtotal =
        lines.fold<int>(0, (s, l) => s + l.quantity * l.product.pricePaise);
    var discount = 0;
    final couponCode = (b['couponCode'] as String?)?.trim().toUpperCase();
    if (couponCode != null && couponCode.isNotEmpty) {
      final c = _coupons[couponCode];
      String? reason;
      if (c == null) {
        reason = 'NOT_FOUND';
      } else if (!c.expiresAt.isAfter(_clock().toUtc())) {
        reason = 'EXPIRED';
      } else if (subtotal < c.minOrderPaise) {
        reason = 'MIN_ORDER_NOT_MET';
      }
      if (reason != null) {
        return _error(409, 'COUPON_INVALID', 'Coupon cannot be applied',
            details: {'code': couponCode, 'reason': reason});
      }
      discount = c!.discountFor(subtotal);
    }
    final afterDiscount = subtotal - discount;
    final fee = (_config['delivery_fee_paise'] as num?)?.toInt() ?? 2500;
    final threshold =
        (_config['free_delivery_threshold_paise'] as num?)?.toInt() ?? 19900;
    final deliveryFee = afterDiscount >= threshold ? 0 : fee;
    final total = afterDiscount + deliveryFee;

    final expectedTotal = b['expectedTotalPaise'];
    if (expectedTotal is! int || expectedTotal != total) {
      return _error(409, 'TOTAL_MISMATCH',
          'The order total does not match the server total',
          details: {
            'expectedTotalPaise': expectedTotal,
            'serverTotalPaise': total,
            'subtotalPaise': subtotal,
            'discountPaise': discount,
            'deliveryFeePaise': deliveryFee,
          });
    }

    for (final l in lines) {
      l.product.stock -= l.quantity;
    }
    final order = _Order(
      id: 'QK-${_nextOrderNumber++}',
      createdAt: _clock().toUtc(),
      items: [
        for (final l in lines)
          _OrderItem(l.product.id, l.product.name, l.product.emoji,
              l.quantity, l.product.pricePaise),
      ],
      subtotalPaise: subtotal,
      discountPaise: discount,
      deliveryFeePaise: deliveryFee,
      totalPaise: total,
      couponCode: couponCode,
    );
    _orders.add(order);
    if (idempotencyKey != null) {
      _idempotency[idempotencyKey] =
          _IdempotencyRecord(fingerprint, order.id);
    }
    _persistSoon();
    return _ok(_orderJson(order), status: 201);
  }

  // ===================================================================
  // Helpers
  // ===================================================================

  void _maybeDriftPrice() {
    if (!chaos.priceDrift) return;
    final now = _clock();
    final last = _lastPriceDrift ?? now;
    if (now.difference(last) < chaos.priceDriftInterval) return;
    _lastPriceDrift = now;
    final candidates = _products.where((p) => p.active).toList();
    if (candidates.isEmpty) return;
    final p = candidates[_random.nextInt(candidates.length)];
    final pct = 5 + _random.nextInt(11); // 5..15 %
    final up = _random.nextBool();
    final delta = max(100, (p.pricePaise * pct) ~/ 100 ~/ 100 * 100);
    setPrice(p.id, max(100, up ? p.pricePaise + delta : p.pricePaise - delta));
  }

  _Product? _productById(String id) =>
      _products.where((p) => p.id == id).firstOrNullItem;

  _Product _requireProduct(String id) {
    final p = _productById(id);
    if (p == null) throw ArgumentError('Unknown product $id');
    return p;
  }

  Map<String, dynamic> _productJson(_Product p) {
    return {
      'id': p.id,
      'name': p.name,
      'categoryId': p.categoryId,
      'emoji': p.emoji,
      'unit': p.unit,
      'price': p.pricePaise / 100,
      'mrp': p.legacy ? null : p.mrpPaise / 100,
      'stock': p.legacy ? '${p.stock}' : p.stock,
      'maxPerOrder': p.maxPerOrder,
    };
  }

  static const _statusThresholds = {
    'packed': 20,
    'out_for_delivery': 45,
    'delivered': 75,
  };

  static const _statusMessages = {
    'packed': 'Your order is packed and ready 📦',
    'out_for_delivery': 'Your order is out for delivery 🛵',
    'delivered': 'Delivered! Enjoy 🎉',
  };

  int _elapsedSeconds(_Order o) =>
      _clock().toUtc().difference(o.createdAt).inSeconds + o.bonusSeconds;

  String _statusOf(_Order o) {
    final elapsed = _elapsedSeconds(o);
    var status = 'placed';
    for (final entry in _statusThresholds.entries) {
      if (elapsed >= entry.value) status = entry.key;
    }
    return status;
  }

  Map<String, dynamic> _orderJson(_Order o) => {
        'id': o.id,
        'status': _statusOf(o),
        'createdAt': o.createdAt.toIso8601String(),
        'items': o.items
            .map((i) => {
                  'productId': i.productId,
                  'name': i.name,
                  'emoji': i.emoji,
                  'quantity': i.quantity,
                  'unitPricePaise': i.unitPricePaise,
                })
            .toList(),
        'subtotalPaise': o.subtotalPaise,
        'discountPaise': o.discountPaise,
        'deliveryFeePaise': o.deliveryFeePaise,
        'totalPaise': o.totalPaise,
        'couponCode': o.couponCode,
      };

  TransportResponse _ok(Object? body, {int status = 200}) =>
      TransportResponse(status, jsonEncode(body));

  TransportResponse _error(int status, String code, String message,
          {Object? details}) =>
      TransportResponse(
        status,
        jsonEncode({
          'error': code,
          'message': message,
          if (details != null) 'details': details,
        }),
      );
}

/// Read-only view of a product as stored on the server (paise).
class ServerProductSnapshot {
  const ServerProductSnapshot({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.pricePaise,
    required this.mrpPaise,
    required this.stock,
    required this.maxPerOrder,
    required this.active,
  });

  final String id;
  final String name;
  final String categoryId;
  final int pricePaise;
  final int mrpPaise;
  final int stock;
  final int maxPerOrder;
  final bool active;
}

// =====================================================================
// Transport
// =====================================================================

class _MockTransport implements Transport {
  _MockTransport(this._server);

  final MockServer _server;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    _server.requestLog.add(request);
    final chaos = _server.chaos;
    final random = _server._random;

    final latency = chaos.latencyOverride?.call(request) ??
        Duration(
          milliseconds: chaos.maxLatencyMs <= chaos.minLatencyMs
              ? chaos.minLatencyMs
              : chaos.minLatencyMs +
                  random.nextInt(chaos.maxLatencyMs - chaos.minLatencyMs),
        );

    if (chaos.offline) {
      if (latency > Duration.zero) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw const TransportUnreachable();
    }

    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    // Connectivity may have dropped while the request was in flight.
    if (chaos.offline) throw const TransportUnreachable();

    if (chaos.failureRate > 0 && random.nextDouble() < chaos.failureRate) {
      if (random.nextBool()) throw const TransportTimeout();
      return TransportResponse(
        503,
        jsonEncode({
          'error': 'SERVICE_UNAVAILABLE',
          'message': 'Service temporarily unavailable',
        }),
      );
    }

    final response = _server._handle(request);

    final isOrderPost = request.method == 'POST' &&
        request.path.replaceAll(RegExp(r'/+$'), '') == '/v1/orders';
    if (isOrderPost && response.isSuccess) {
      var lose = false;
      if (chaos.loseNextOrderResponses > 0) {
        chaos.loseNextOrderResponses--;
        lose = true;
      } else if (chaos.orderResponseLossRate > 0 &&
          random.nextDouble() < chaos.orderResponseLossRate) {
        lose = true;
      }
      if (lose) throw const TransportTimeout();
    }
    return response;
  }
}

// =====================================================================
// Server-side models (private)
// =====================================================================

class _Category {
  _Category(this.id, this.name, this.emoji);

  factory _Category.fromDb(Map<String, dynamic> m) =>
      _Category(m['id'] as String, m['name'] as String, m['emoji'] as String);

  final String id;
  final String name;
  final String emoji;

  Map<String, dynamic> toDb() => {'id': id, 'name': name, 'emoji': emoji};
  Map<String, dynamic> toJson() => toDb();
}

class _Product {
  _Product({
    required this.id,
    required this.categoryId,
    required this.emoji,
    required this.name,
    required this.unit,
    required this.pricePaise,
    required this.mrpPaise,
    required this.stock,
    required this.maxPerOrder,
    required this.active,
    required this.legacy,
  });

  factory _Product.fromDb(Map<String, dynamic> m) => _Product(
        id: m['id'] as String,
        categoryId: m['categoryId'] as String,
        emoji: m['emoji'] as String,
        name: m['name'] as String,
        unit: m['unit'] as String,
        pricePaise: m['pricePaise'] as int,
        mrpPaise: m['mrpPaise'] as int,
        stock: m['stock'] as int,
        maxPerOrder: m['maxPerOrder'] as int,
        active: m['active'] as bool,
        legacy: m['legacy'] as bool,
      );

  final String id;
  final String categoryId;
  final String emoji;
  final String name;
  final String unit;
  int pricePaise;
  int mrpPaise;
  int stock;
  int maxPerOrder;
  bool active;
  final bool legacy;

  Map<String, dynamic> toDb() => {
        'id': id,
        'categoryId': categoryId,
        'emoji': emoji,
        'name': name,
        'unit': unit,
        'pricePaise': pricePaise,
        'mrpPaise': mrpPaise,
        'stock': stock,
        'maxPerOrder': maxPerOrder,
        'active': active,
        'legacy': legacy,
      };
}

class _Coupon {
  _Coupon(this.code, this.type, this.value, this.maxDiscountPaise,
      this.minOrderPaise, this.expiresAt, this.description);

  factory _Coupon.fromDb(Map<String, dynamic> m) => _Coupon(
        m['code'] as String,
        m['type'] as String,
        m['value'] as int,
        m['maxDiscountPaise'] as int?,
        m['minOrderPaise'] as int,
        DateTime.parse(m['expiresAt'] as String),
        m['description'] as String,
      );

  final String code;
  final String type; // flat | percent
  final int value; // paise for flat, percent for percent
  final int? maxDiscountPaise;
  final int minOrderPaise;
  DateTime expiresAt;
  final String description;

  int discountFor(int subtotalPaise) {
    if (subtotalPaise < minOrderPaise) return 0;
    if (type == 'flat') return min(value, subtotalPaise);
    final raw = subtotalPaise * value ~/ 100;
    return maxDiscountPaise == null ? raw : min(raw, maxDiscountPaise!);
  }

  Map<String, dynamic> toDb() => toJson();

  Map<String, dynamic> toJson() => {
        'code': code,
        'type': type,
        'value': value,
        'maxDiscountPaise': maxDiscountPaise,
        'minOrderPaise': minOrderPaise,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'description': description,
      };
}

class _OrderItem {
  _OrderItem(this.productId, this.name, this.emoji, this.quantity,
      this.unitPricePaise);

  final String productId;
  final String name;
  final String emoji;
  final int quantity;
  final int unitPricePaise;
}

class _Order {
  _Order({
    required this.id,
    required this.createdAt,
    required this.items,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.deliveryFeePaise,
    required this.totalPaise,
    required this.couponCode,
    this.bonusSeconds = 0,
  });

  factory _Order.fromDb(Map<String, dynamic> m) => _Order(
        id: m['id'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        items: (m['items'] as List).map((e) {
          final i = e as Map<String, dynamic>;
          return _OrderItem(
            i['productId'] as String,
            i['name'] as String,
            i['emoji'] as String,
            i['quantity'] as int,
            i['unitPricePaise'] as int,
          );
        }).toList(),
        subtotalPaise: m['subtotalPaise'] as int,
        discountPaise: m['discountPaise'] as int,
        deliveryFeePaise: m['deliveryFeePaise'] as int,
        totalPaise: m['totalPaise'] as int,
        couponCode: m['couponCode'] as String?,
        bonusSeconds: m['bonusSeconds'] as int? ?? 0,
      );

  final String id;
  final DateTime createdAt;
  final List<_OrderItem> items;
  final int subtotalPaise;
  final int discountPaise;
  final int deliveryFeePaise;
  final int totalPaise;
  final String? couponCode;
  int bonusSeconds;

  Map<String, dynamic> toDb() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'items': items
            .map((i) => {
                  'productId': i.productId,
                  'name': i.name,
                  'emoji': i.emoji,
                  'quantity': i.quantity,
                  'unitPricePaise': i.unitPricePaise,
                })
            .toList(),
        'subtotalPaise': subtotalPaise,
        'discountPaise': discountPaise,
        'deliveryFeePaise': deliveryFeePaise,
        'totalPaise': totalPaise,
        'couponCode': couponCode,
        'bonusSeconds': bonusSeconds,
      };
}

class _IdempotencyRecord {
  _IdempotencyRecord(this.fingerprint, this.orderId);

  factory _IdempotencyRecord.fromDb(Map<String, dynamic> m) =>
      _IdempotencyRecord(m['fingerprint'] as String, m['orderId'] as String);

  final String fingerprint;
  final String orderId;

  Map<String, dynamic> toDb() => {'fingerprint': fingerprint, 'orderId': orderId};
}

extension _FirstOrNullItem<T> on Iterable<T> {
  T? get firstOrNullItem {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
