import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  static const _cacheKey = 'app_config.cached_values';

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  ///
  /// On success persists the values; on failure uses the last known good config;
  /// with nothing cached uses defaults. It must never throw.
  Future<AppConfig> load({bool bypassCache = true}) async {
    try {
      final json = await _client.get('/v1/config', bypassCache: bypassCache)
          as Map<String, dynamic>;
      final values = (json['values'] as Map).cast<String, Object?>();
      await _store.setString(_cacheKey, jsonEncode(values));
      return AppConfig.fromValues(values);
    } catch (_) {
      try {
        final cachedRaw = await _store.getString(_cacheKey);
        if (cachedRaw != null) {
          final cachedValues =
              (jsonDecode(cachedRaw) as Map).cast<String, Object?>();
          return AppConfig.fromValues(cachedValues);
        }
      } catch (_) {
        // Fall back to defaults on corrupt cache
      }
      return AppConfig.defaults();
    }
  }
}
