import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock_server/mock_server.dart';
import 'network/api_client.dart';
import 'storage/key_value_store.dart';

/// Version of this build. Can be overridden from Dev Tools to test update
/// flows (see [appVersionProvider]).
const String kAppVersion = '1.4.0';

/// Persistent key-value storage. Overridden in `main.dart` and in tests.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError('keyValueStoreProvider must be overridden'),
);

/// The in-process mock backend. Overridden in `main.dart` and in tests.
final mockServerProvider = Provider<MockServer>(
  (ref) => throw UnimplementedError('mockServerProvider must be overridden'),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(mockServerProvider).transport),
);

/// The version the app believes it is running.
final appVersionProvider = Provider<String>((ref) => kAppVersion);

/// Storage key used by Dev Tools to fake the installed app version.
const String kDebugAppVersionKey = 'dev_tools.app_version_override';
