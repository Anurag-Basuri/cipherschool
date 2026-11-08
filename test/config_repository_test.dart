import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('ConfigRepository caches config and survives offline start', () async {
    final repo = h.container.read(configRepositoryProvider);

    // Initial load succeeds and persists config
    h.server.publishConfig({
      'store_closed_message': 'Custom closed message',
    });
    final config1 = await repo.load();
    expect(config1.storeClosedMessage, 'Custom closed message');

    // Simulate app restart offline
    h.server.chaos.offline = true;
    final restarted = h.restart();
    addTearDown(restarted.dispose);

    final restartedRepo = restarted.container.read(configRepositoryProvider);
    final cachedConfig = await restartedRepo.load();
    expect(cachedConfig.storeClosedMessage, 'Custom closed message');
  });

  test('ConfigRepository never throws and falls back to defaults with no cache',
      () async {
    h.server.chaos.offline = true;
    final repo = h.container.read(configRepositoryProvider);

    final config = await repo.load();
    expect(config.deliveryFeePaise, 2500);
    expect(config.freeDeliveryThresholdPaise, 19900);
    expect(config.storeOpen, isTrue);
  });

  test('AppConfigController updates automatically on remoteUpdates stream',
      () async {
    // Read controller to establish subscription
    final controller =
        h.container.read(appConfigControllerProvider.notifier);
    expect(h.container.read(appConfigControllerProvider).storeOpen, isTrue);

    // Publish update
    h.server.publishConfig({'store_open': false});

    // Wait for stream event to propagate and load() to finish
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(h.container.read(appConfigControllerProvider).storeOpen, isFalse);
  });
}
