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
      return const CheckoutFailure(
        'An order is already being placed.',
        canRetry: false,
      );
    }
    state = const CheckoutState(isPlacingOrder: true);
    try {
      final result = await _executeCheckout();
      state = CheckoutState(lastResult: result);
      return result;
    } finally {
      if (state.isPlacingOrder) {
        state = CheckoutState(isPlacingOrder: false, lastResult: state.lastResult);
      }
    }
  }

  Future<CheckoutResult> _executeCheckout() async {
    // 1. Store closed guard (checked without sending any network request)
    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) {
      return CheckoutFailure(config.storeClosedMessage, canRetry: false);
    }

    // 2. Empty cart guard
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty', canRetry: false);
    }

    // 3. Reconcile cart before placing order
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

    final orderCart = reconciliation.cart;
    if (orderCart.isEmpty) {
      return const CheckoutFailure('Your cart is empty', canRetry: false);
    }

    // 4. Idempotency Key generation & retrieval
    final store = ref.read(keyValueStoreProvider);
    final fingerprint = _cartFingerprint(orderCart);
    final storedFingerprint =
        await store.getString('checkout.pending_fingerprint');
    String? idempotencyKey;
    if (storedFingerprint == fingerprint) {
      idempotencyKey = await store.getString('checkout.pending_key');
    }
    if (idempotencyKey == null || idempotencyKey.isEmpty) {
      idempotencyKey =
          'QK-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(999999)}';
      await store.setString('checkout.pending_fingerprint', fingerprint);
      await store.setString('checkout.pending_key', idempotencyKey);
    }

    final pricing = CartPricing.compute(orderCart, config);

    // 5. Send order request with idempotency key and safe retry on timeout
    try {
      final order = await _sendWithRetry(
        orderCart,
        pricing,
        idempotencyKey,
        retryOnTimeout: true,
      );
      await store.remove('checkout.pending_fingerprint');
      await store.remove('checkout.pending_key');
      await ref.read(cartControllerProvider.notifier).clear();
      ref.invalidate(ordersProvider);
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      return const CheckoutFailure(
        'The request timed out. Your order may have been placed. Please check My orders before trying again.',
        canRetry: true,
      );
    } on ClientException catch (e) {
      if (e.statusCode == 503 || e.code == 'STORE_CLOSED') {
        return CheckoutFailure(e.message, canRetry: false);
      }
      if (e.statusCode == 409 || e.statusCode == 422) {
        try {
          final reReconcile = await reconciler.reconcile(orderCart);
          await ref
              .read(cartControllerProvider.notifier)
              .replace(reReconcile.cart);
          return CheckoutNeedsReview(reReconcile);
        } catch (_) {
          return CheckoutFailure(e.message, canRetry: false);
        }
      }
      return CheckoutFailure(e.message, canRetry: false);
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }

  Future<Order> _sendWithRetry(
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
        return _sendWithRetry(
          cart,
          pricing,
          idempotencyKey,
          retryOnTimeout: false,
        );
      }
      rethrow;
    }
  }

  String _cartFingerprint(Cart cart) {
    final lines = cart.lines
        .map((l) => '${l.productId}:${l.quantity}:${l.unitPricePaise}')
        .join('|');
    return '$lines;coupon=${cart.coupon?.code}';
  }
}
