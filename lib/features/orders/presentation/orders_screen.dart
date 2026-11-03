import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../checkout/domain/order.dart';
import '../data/order_tracking_repository.dart';

/// Order history.
///
/// TODO(F3, optional): show live status for active orders and in-app
/// notifications when the status changes. See ASSIGNMENT.md.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(ordersProvider.future),
        child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Could not load orders\n$e',
                  textAlign: TextAlign.center)),
            ],
          ),
          data: (items) => items.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No orders yet')),
                  ],
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _OrderTile(order: items[index]),
                ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final local = order.createdAt.toLocal();
    final time =
        '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return ListTile(
      leading: Text(order.items.first.emoji,
          style: const TextStyle(fontSize: 28)),
      title: Text('${order.id} • ${formatMoney(order.totalPaise)}'),
      subtitle: Text('${order.itemCount} items • $time'),
      trailing: Chip(label: Text(order.status.label)),
    );
  }
}
