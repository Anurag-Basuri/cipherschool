import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money.dart';
import '../../../cart/application/cart_controller.dart';
import '../../domain/product.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(product.emoji,
                        style: const TextStyle(fontSize: 40)),
                  ),
                  if (product.hasDiscount)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(product.unit,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            if (product.inStock && product.stock <= 3)
              Text('Only ${product.stock} left',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.deepOrange)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatMoney(product.pricePaise),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      if (product.hasDiscount)
                        Text(
                          formatMoney(product.mrpPaise),
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                AddToCartButton(product: product),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "ADD" button that turns into a - qty + stepper.
class AddToCartButton extends ConsumerWidget {
  const AddToCartButton({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = ref.watch(
        cartControllerProvider.select((cart) => cart.lineFor(product.id)));
    final cart = ref.read(cartControllerProvider.notifier);

    if (!product.inStock && line == null) {
      return const Text('Out of stock',
          style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    if (line == null) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: Colors.green.shade800,
          side: BorderSide(color: Colors.green.shade800),
        ),
        onPressed: () => cart.add(product),
        child: const Text('ADD'),
      );
    }
    return QuantityStepper(
      quantity: line.quantity,
      canIncrement: line.quantity < line.maxPerOrder,
      onIncrement: () => cart.increment(product.id),
      onDecrement: () => cart.decrement(product.id),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.canIncrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final bool canIncrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final color = Colors.green.shade800;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperIcon(icon: Icons.remove, onTap: onDecrement),
          Text('$quantity',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          _StepperIcon(icon: Icons.add, onTap: canIncrement ? onIncrement : null),
        ],
      ),
    );
  }
}

class _StepperIcon extends StatelessWidget {
  const _StepperIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(icon,
            size: 16, color: onTap == null ? Colors.white38 : Colors.white),
      ),
    );
  }
}
