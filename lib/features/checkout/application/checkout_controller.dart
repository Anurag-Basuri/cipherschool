import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../../orders/data/order_tracking_repository.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() async {
    if (state.isPlacingOrder) {
      return const CheckoutFailure('An order is already in progress.');
    }

    state = const CheckoutState(isPlacingOrder: true);
    try {
      final result = await _placeOrder();
      state = CheckoutState(lastResult: result);
      return result;
    } finally {
      if (state.isPlacingOrder) {
        state = CheckoutState(lastResult: state.lastResult);
      }
    }
  }

  Future<CheckoutResult> _placeOrder() async {
    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) {
      return CheckoutFailure(config.storeClosedMessage);
    }

    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }

    // Verify current prices, stock and discounts before charging the user.
    final reconciler = ref.read(cartReconcilerProvider);
    final ReconciliationResult reconciliation;
    try {
      reconciliation = await reconciler.reconcile(cart);
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }

    if (reconciliation.requiresUserReview) {
      await ref
          .read(cartControllerProvider.notifier)
          .replace(reconciliation.cart);
      return CheckoutNeedsReview(reconciliation);
    }

    if (reconciliation.hasChanges) {
      await ref
          .read(cartControllerProvider.notifier)
          .replace(reconciliation.cart);
    }

    final currentCart = reconciliation.cart;
    if (currentCart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }

    // Reuse or generate an idempotency key tied to this exact cart snapshot.
    final key = await _getOrCreateIdempotencyKey(currentCart);
    final pricing = CartPricing.compute(currentCart, config);

    try {
      final order = await _sendOrder(
        currentCart,
        pricing,
        key,
        retryOnTimeout: true,
      );
      await _clearIdempotencyKey();
      await ref.read(cartControllerProvider.notifier).clear();
      ref.invalidate(ordersProvider);
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      return const CheckoutFailure(
        'The request timed out. Your order may have been placed. '
        'Please check My orders before trying again.',
        canRetry: true,
      );
    } on ClientException catch (e) {
      if (e.statusCode == 503 || e.code == 'STORE_CLOSED') {
        return CheckoutFailure(e.message);
      }
      if (e.statusCode == 409 || e.statusCode == 422) {
        try {
          final refreshed = await reconciler.reconcile(currentCart);
          await ref
              .read(cartControllerProvider.notifier)
              .replace(refreshed.cart);
          return CheckoutNeedsReview(refreshed);
        } catch (_) {
          return CheckoutFailure(e.message);
        }
      }
      return CheckoutFailure(e.message);
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }

  Future<Order> _sendOrder(
    Cart cart,
    CartPricing pricing,
    String idempotencyKey, {
    required bool retryOnTimeout,
  }) async {
    try {
      return await ref.read(orderApiProvider).placeOrder(
            cart,
            pricing,
            idempotencyKey: idempotencyKey,
          );
    } on ApiTimeoutException {
      if (retryOnTimeout) {
        return _sendOrder(
          cart,
          pricing,
          idempotencyKey,
          retryOnTimeout: false,
        );
      }
      rethrow;
    }
  }

  Future<String> _getOrCreateIdempotencyKey(Cart cart) async {
    final store = ref.read(keyValueStoreProvider);
    final fingerprint = _cartFingerprint(cart);
    final savedFingerprint =
        await store.getString('checkout.idemp_fingerprint');

    if (savedFingerprint == fingerprint) {
      final existingKey = await store.getString('checkout.idemp_key');
      if (existingKey != null && existingKey.isNotEmpty) {
        return existingKey;
      }
    }

    final newKey =
        'QK-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(100000)}';
    await store.setString('checkout.idemp_fingerprint', fingerprint);
    await store.setString('checkout.idemp_key', newKey);
    return newKey;
  }

  Future<void> _clearIdempotencyKey() async {
    final store = ref.read(keyValueStoreProvider);
    await store.remove('checkout.idemp_fingerprint');
    await store.remove('checkout.idemp_key');
  }

  String _cartFingerprint(Cart cart) {
    final lines = cart.lines
        .map((l) => '${l.productId}:${l.quantity}:${l.unitPricePaise}')
        .join(',');
    return '$lines;${cart.coupon?.code}';
  }
}
