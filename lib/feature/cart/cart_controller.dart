import 'package:get/get.dart';

import '../../repository/order_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

/// Checkout coordinator for the bag.
///
/// F-3 responsibilities beyond the pre-existing checkout call:
///   1. **Proactive expiry guard.** If any line's reservation has lapsed
///      locally, block the round-trip and prompt the user to refresh the
///      affected lines. Prevents a guaranteed 410 and keeps the failure
///      close to the affordance (the Refresh button on the offending
///      line).
///   2. **410 survival.** If the server rejects a reservation anyway (clock
///      skew, or the local check was OK but the round-trip crossed the
///      expiry boundary), surface the failure in the same shape as the
///      proactive guard — no crash, no data loss, user sees exactly what
///      to do.
///   3. **Non-410 error handling** kept as-is (snackbar with the API's
///      message).
class CartController extends GetxController {
  final CartService cartService;
  final OrderRepo orderRepo;

  CartController({required this.cartService, required this.orderRepo});

  final isCheckingOut = false.obs;

  AnalyticsService? get _analytics =>
      Get.isRegistered<AnalyticsService>() ? Get.find<AnalyticsService>() : null;

  Future<void> checkout() async {
    if (cartService.items.isEmpty || isCheckingOut.value) return;

    // Proactive local check — no point posting a batch we already know is
    // stale. Also gives the user precise per-line guidance ("Refresh these
    // 2 items") rather than a bulk failure.
    final expired = cartService.items
        .where(cartService.isReservationExpired)
        .toList(growable: false);
    if (expired.isNotEmpty) {
      _analytics?.logEvent('checkout_blocked_expired_holds', {
        'expired_count': expired.length,
      });
      Get.snackbar(
        'Some holds expired',
        'Refresh ${expired.length} item${expired.length == 1 ? '' : 's'} in your bag before checking out.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    isCheckingOut.value = true;
    try {
      final order = await orderRepo.checkout(cartService.items.toList());
      cartService.clearAfterCheckout();
      _analytics?.logEvent('checkout_success', {'order_id': order.id});
      Get.snackbar(
        'Order confirmed',
        'Order #${order.id} — pick up soon!',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on ApiException catch (e) {
      LogService.error('checkout failed', e);
      if (e.statusCode == 410) {
        // Server-observed expiry. We can't tell which item without a
        // richer error shape; the local expired-check will have caught
        // most cases already, so this path is race-with-the-clock only.
        // Same UX as the proactive block — direct the user to refresh.
        _analytics
            ?.logEvent('checkout_rejected_stale_hold', {'status': e.statusCode});
        Get.snackbar(
          'Hold expired mid-checkout',
          'One or more items lost their hold. Tap the refresh icon on affected lines and try again.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        _analytics
            ?.logEvent('checkout_failed', {'status': e.statusCode});
        Get.snackbar(
          'Checkout failed',
          e.message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
    isCheckingOut.value = false;
  }
}
