import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
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
  // ignore: unused_field
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  Future<AppConfig> load({bool bypassCache = true}) async {
    try {
      final json = await _client.get('/v1/config', bypassCache: bypassCache)
          as Map<String, dynamic>;
      final values = (json['values'] as Map).cast<String, Object?>();
      return AppConfig.fromValues(values);
    } on ApiException {
      return AppConfig.defaults();
    }
  }
}
