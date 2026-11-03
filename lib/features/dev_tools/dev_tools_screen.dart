import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/money.dart';
import '../cart/application/cart_controller.dart';
import '../catalog/data/catalog_repository.dart';

/// Developer tools: control the mock backend and the simulated network.
///
/// This screen plays the role of the backend team, the Firebase console and
/// a flaky mobile network. It is part of the assignment infrastructure; you
/// do not need to change it (but you may add tools if they help you).
class DevToolsScreen extends ConsumerStatefulWidget {
  const DevToolsScreen({super.key});

  @override
  ConsumerState<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends ConsumerState<DevToolsScreen> {
  final _versionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _versionController.text = ref.read(appVersionProvider);
  }

  @override
  void dispose() {
    _versionController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(mockServerProvider);
    final chaos = server.chaos;

    return Scaffold(
      appBar: AppBar(title: const Text('🛠 Dev tools')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          const _Header('Network'),
          SwitchListTile(
            title: const Text('Offline (no internet)'),
            value: chaos.offline,
            onChanged: (v) => setState(() => chaos.offline = v),
          ),
          ListTile(
            title: const Text('Latency'),
            subtitle: Wrap(
              spacing: 8,
              children: [
                for (final preset in const [
                  ('Fast', 0, 50),
                  ('Normal', 250, 1200),
                  ('Slow 3G', 1500, 4000),
                ])
                  ChoiceChip(
                    label: Text(preset.$1),
                    selected: chaos.minLatencyMs == preset.$2 &&
                        chaos.maxLatencyMs == preset.$3,
                    onSelected: (_) => setState(() {
                      chaos.minLatencyMs = preset.$2;
                      chaos.maxLatencyMs = preset.$3;
                    }),
                  ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Random request failures'),
            subtitle: Wrap(
              spacing: 8,
              children: [
                for (final rate in const [0.0, 0.08, 0.3])
                  ChoiceChip(
                    label: Text('${(rate * 100).round()}%'),
                    selected: chaos.failureRate == rate,
                    onSelected: (_) =>
                        setState(() => chaos.failureRate = rate),
                  ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Lost order responses'),
            subtitle: Text(
                'Server processes the order but the app never gets the '
                'response. Random rate: '
                '${(chaos.orderResponseLossRate * 100).round()}% • '
                'queued: ${chaos.loseNextOrderResponses}'),
            trailing: OutlinedButton(
              onPressed: () {
                setState(() => chaos.loseNextOrderResponses++);
                _toast('The next order response will be lost');
              },
              child: const Text('Lose next'),
            ),
          ),
          SwitchListTile(
            title: const Text('Random order response loss (10%)'),
            value: chaos.orderResponseLossRate > 0,
            onChanged: (v) =>
                setState(() => chaos.orderResponseLossRate = v ? 0.10 : 0),
          ),

          const _Header('Catalog & cart (backend)'),
          SwitchListTile(
            title: const Text('Price drift'),
            subtitle: const Text(
                'A random product changes price every ~90s'),
            value: chaos.priceDrift,
            onChanged: (v) => setState(() => chaos.priceDrift = v),
          ),
          ListTile(
            leading: const Icon(Icons.price_change_outlined),
            title: const Text('Change a random product price now'),
            onTap: () {
              final ids = server.productIds;
              final id = ids[Random().nextInt(ids.length)];
              final p = server.product(id);
              final newPrice = p.pricePaise + 1000;
              server.setPrice(id, newPrice);
              _toast('${p.name}: ${formatMoney(p.pricePaise)} → '
                  '${formatMoney(newPrice)}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('Create conflicts for my cart'),
            subtitle: const Text(
                'Item 1 price +15%, item 2 out of stock, item 3 only 1 left, '
                'item 4 discontinued, applied coupon expires'),
            onTap: () {
              final cart = ref.read(cartControllerProvider);
              if (cart.isEmpty) {
                _toast('Add a few items to your cart first');
                return;
              }
              server.simulateCartConflicts(
                cart.lines.map((l) => l.productId).toList(),
                couponCode: cart.coupon?.code,
              );
              _toast('Conflicts created on the server');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear on-device catalog cache'),
            onTap: () async {
              await ref.read(catalogCacheProvider).clear();
              _toast('Catalog cache cleared');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.red),
            title: const Text('Reset ALL server data'),
            subtitle: const Text('Prices, stock, coupons, orders, config'),
            onTap: () async {
              await server.resetData();
              setState(() {});
              _toast('Server data reset');
            },
          ),

          const _Header('Remote config (console)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _preset('Close store', {'store_open': false}),
                _preset('Open store', {'store_open': true}),
                _preset('Soft update (latest 1.5.0)',
                    {'latest_version': '1.5.0'}),
                _preset('Force update (min 2.0.0)',
                    {'min_supported_version': '2.0.0',
                     'latest_version': '2.0.0'}),
                _preset('Reset versions', {
                  'min_supported_version': '1.0.0',
                  'latest_version': '1.4.0',
                }),
                _preset('Free delivery ≥ ₹99',
                    {'free_delivery_threshold_paise': 9900}),
                _preset('Sections: deals first', {
                  'home_sections':
                      jsonEncode(['deals', 'banner', 'all_products']),
                }),
                _preset('Sections: unknown type', {
                  'home_sections': jsonEncode(
                      ['banner', 'video_carousel', 'categories', 'all_products']),
                }),
                _preset('Sections: malformed', {'home_sections': '[banner,'}),
              ],
            ),
          ),
          for (final entry in server.configValues.entries)
            ListTile(
              dense: true,
              title: Text(entry.key),
              subtitle: Text('${entry.value}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _editConfig(entry.key, entry.value),
            ),
          ListTile(
            dense: true,
            title: Text('Config version: ${server.configVersion}'),
          ),

          const _Header('App version'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _versionController,
                    decoration: const InputDecoration(
                      labelText: 'Pretend installed version',
                      helperText: 'Restart the app to apply',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () async {
                    await ref.read(keyValueStoreProvider).setString(
                        kDebugAppVersionKey, _versionController.text.trim());
                    _toast('Saved. Fully restart the app to apply.');
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),

          const _Header('Orders (backend)'),
          if (server.orders.isEmpty)
            const ListTile(title: Text('No orders yet')),
          for (final o in server.orders.take(5))
            ListTile(
              dense: true,
              title: Text('${o['id']} • ${o['status']}'),
              subtitle: Text(formatMoney(o['totalPaise'] as int)),
              trailing: OutlinedButton(
                onPressed: () {
                  server.advanceOrder(o['id'] as String);
                  setState(() {});
                },
                child: const Text('Advance'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preset(String label, Map<String, Object?> values) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        ref.read(mockServerProvider).publishConfig(values);
        setState(() {});
        _toast('Published: ${values.keys.join(', ')}');
      },
    );
  }

  Future<void> _editConfig(String key, Object? current) async {
    final controller = TextEditingController(text: '${current ?? ''}');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(key),
        content: TextField(controller: controller, maxLines: null),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    Object? value = result;
    if (current is bool) {
      value = result.trim().toLowerCase() == 'true';
    } else if (current is int) {
      value = int.tryParse(result.trim()) ?? result;
    }
    ref.read(mockServerProvider).publishConfig({key: value});
    setState(() {});
    _toast('Published $key');
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}
