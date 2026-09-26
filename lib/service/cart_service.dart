import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';
import 'analytics_service.dart';
import 'countdown_ticker.dart';

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
class CartService extends GetxService {
  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  Worker? _expiryWatcher;

  @override
  void onInit() {
    super.onInit();
    // Prune flash-sale items when their countdown reaches zero. Registered
    // once and disposed in onClose so the Worker doesn't leak — same shape
    // as the RES-103 fix. The tick fires once a second app-wide; the check
    // is an O(n) sweep of the cart, which is tiny.
    if (Get.isRegistered<CountdownTicker>()) {
      final ticker = Get.find<CountdownTicker>();
      _expiryWatcher = ever(ticker.now, _pruneExpiredFlashSales);
    }
  }

  @override
  void onClose() {
    _expiryWatcher?.dispose();
    super.onClose();
  }

  void add(DealModel deal) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
    }
    _recount();
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      items.removeWhere((i) => i.deal.id == dealId);
    } else {
      items.refresh();
    }
    _recount();
  }

  void remove(int dealId) {
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  void _pruneExpiredFlashSales(DateTime now) {
    final expired = items
        .where((i) =>
            i.deal.flashSaleEndsAt != null &&
            !i.deal.flashSaleEndsAt!.isAfter(now))
        .toList(growable: false);
    if (expired.isEmpty) return;
    items.removeWhere(
        (i) => expired.any((e) => e.deal.id == i.deal.id));
    _recount();
    for (final item in expired) {
      LogService.log('cart: removed expired flash deal ${item.deal.id}');
      if (Get.isRegistered<AnalyticsService>()) {
        Get.find<AnalyticsService>().logEvent('flash_deal_removed_from_bag', {
          'deal_id': item.deal.id,
          'quantity': item.quantity,
        });
      }
      _notifyRemoved(item);
    }
  }

  void _notifyRemoved(CartItemModel item) {
    // Only surface a snackbar if we're inside a running app — tests and
    // background contexts don't have an overlay.
    if (Get.context == null) return;
    Get.snackbar(
      'Flash sale ended',
      '${item.deal.name} was removed from your bag.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.timer_off, color: Colors.white),
      backgroundColor: Colors.black87,
      colorText: Colors.white,
    );
  }
}
