import 'dart:convert';

import '../../../core/storage/key_value_store.dart';
import '../domain/product.dart';

/// On-device cache of catalog pages, so the app can show products offline.
class CatalogCache {
  CatalogCache(this._store, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final DateTime Function() _clock;

  static const _prefix = 'catalog_cache.';

  Future<CachedCatalogPage?> read(String key) async {
    final raw = await _store.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CachedCatalogPage(
        page: CatalogPage.fromCacheJson(json['page'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
    } catch (_) {
      // A corrupt entry (e.g. written by an older app version) is treated
      // as a cache miss. Do not crash the catalog because of the cache.
      return null;
    }
  }

  Future<void> write(String key, CatalogPage page) {
    return _store.setString(
      '$_prefix$key',
      jsonEncode({
        'savedAt': _clock().toIso8601String(),
        'page': page.toCacheJson(),
      }),
    );
  }

  Future<void> clear() async {
    for (final key in await _store.keys()) {
      if (key.startsWith(_prefix)) await _store.remove(key);
    }
  }
}

class CachedCatalogPage {
  const CachedCatalogPage({required this.page, required this.savedAt});

  final CatalogPage page;
  final DateTime savedAt;
}
