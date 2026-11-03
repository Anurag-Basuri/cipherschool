import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/cart.dart';

final cartStorageProvider = Provider<CartStorage>(
  (ref) => CartStorage(ref.watch(keyValueStoreProvider)),
);

/// Persists the cart so it survives app restarts.
class CartStorage {
  CartStorage(this._store);

  final KeyValueStore _store;

  static const _key = 'cart.v1';

  Future<Cart> load() async {
    final raw = await _store.getString(_key);
    if (raw == null) return const Cart.empty();
    try {
      return Cart.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Cart.empty();
    }
  }

  Future<void> save(Cart cart) => _store.setString(_key, jsonEncode(cart));

  Future<void> clear() => _store.remove(_key);
}
