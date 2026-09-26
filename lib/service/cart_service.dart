import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../repository/order_repo.dart';
import '../util/log_service.dart';
import 'analytics_service.dart';
import 'api_exception.dart';
import 'countdown_ticker.dart';

/// App-wide cart with real stock reservations (F-3).
///
/// Every fresh add optimistically inserts the line and then attempts to
/// [OrderRepo.reserve] a 5-minute hold on the deal's stock. If the hold
/// fails (409, roughly every 5th mutation on the fake API), the line is
/// rolled back and the caller is notified. Removing a line releases the
/// hold. Reservation expiry mid-session is handled passively — the line
/// stays with a "Refresh" affordance so the user can attempt to reclaim
/// stock rather than losing the intent. See `docs/evidence/f-3.md` for
/// the full expiry-behaviour rationale.
class CartService extends GetxService {
  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// dealIds whose fresh add is still awaiting the reserve round-trip. The
  /// UI reads this to show a "Reserving…" spinner on the line.
  final reservingDealIds = <int>{}.obs;

  Worker? _expiryWatcher;

  OrderRepo get _orderRepo => Get.find<OrderRepo>();
  AnalyticsService? get _analytics =>
      Get.isRegistered<AnalyticsService>() ? Get.find<AnalyticsService>() : null;
  CountdownTicker? get _ticker => Get.isRegistered<CountdownTicker>()
      ? Get.find<CountdownTicker>()
      : null;

  @override
  void onInit() {
    super.onInit();
    final ticker = _ticker;
    if (ticker != null) {
      _expiryWatcher = ever(ticker.now, _pruneExpiredFlashSales);
    }
  }

  @override
  void onClose() {
    _expiryWatcher?.dispose();
    super.onClose();
  }

  // -------------------------------------------------------------------- adds

  /// Optimistically inserts [deal] into the bag and asynchronously reserves
  /// stock. On reserve failure the line is removed and a caller-friendly
  /// message is surfaced. Increments of an existing line are local-only —
  /// the reservation set at the first add remains authoritative until the
  /// user removes or refreshes the line. Deliberate simplification (see
  /// evidence doc); the fake API's per-item reservation shape supports a
  /// stricter reconcile-quantity flow but we're not doing that here.
  Future<void> add(DealModel deal) async {
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return;
      }
      existing.quantity++;
      items.refresh();
      _recount();
      return;
    }

    // Fresh optimistic insert.
    final placeholder = CartItemModel(deal: deal);
    items.add(placeholder);
    reservingDealIds.add(deal.id);
    _recount();

    try {
      final reservation = await _orderRepo.reserve(deal.id, quantity: 1);
      final line = items.firstWhereOrNull((i) => i.deal.id == deal.id);
      if (line == null) {
        // The user removed the line before the reserve returned. Release
        // the orphan hold so we don't hold stock the user doesn't want.
        _orderRepo
            .releaseReservation(reservation.id)
            .catchError((Object e) => LogService.error('orphan release', e));
        return;
      }
      line.reservation = reservation;
      items.refresh();
      _analytics?.logEvent('reservation_created', {
        'deal_id': deal.id,
        'reservation_id': reservation.id,
      });
    } on ApiException catch (e) {
      // Roll back the optimistic insert.
      items.removeWhere((i) => i.deal.id == deal.id);
      _recount();
      _analytics?.logEvent('reservation_failed', {
        'deal_id': deal.id,
        'status': e.statusCode,
      });
      _notify(
        'Someone grabbed the last one',
        e.statusCode == 409
            ? 'That deal sold out while we were reserving yours. Try another?'
            : e.message,
      );
    } finally {
      reservingDealIds.remove(deal.id);
    }
  }

  // ---------------------------------------------------------------- removals

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      _removeAndRelease(dealId);
      return;
    }
    items.refresh();
    _recount();
  }

  void remove(int dealId) => _removeAndRelease(dealId);

  void clear() {
    final toRelease = items
        .where((i) => i.reservation != null)
        .map((i) => i.reservation!.id)
        .toList(growable: false);
    items.clear();
    _recount();
    for (final id in toRelease) {
      _releaseSilently(id);
    }
  }

  /// Called after a successful checkout — server has consumed the holds, so
  /// there's nothing to release. Just clears local state.
  void clearAfterCheckout() {
    items.clear();
    _recount();
  }

  void _removeAndRelease(int dealId) {
    final line = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (line == null) return;
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
    final resId = line.reservation?.id;
    if (resId != null) {
      _releaseSilently(resId);
    }
  }

  void _releaseSilently(String reservationId) {
    _orderRepo.releaseReservation(reservationId).catchError(
      (Object e) {
        LogService.error('release failed for $reservationId', e);
      },
    );
  }

  // ---------------------------------------------------------------- refresh

  /// User-initiated re-reserve after a hold expired. Keeps the line in the
  /// bag either way — success replaces the reservation, failure surfaces
  /// the reason but doesn't clobber the line so the user can try again.
  Future<void> refreshHold(int dealId) async {
    final line = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (line == null) return;
    if (reservingDealIds.contains(dealId)) return;
    reservingDealIds.add(dealId);
    try {
      final reservation =
          await _orderRepo.reserve(dealId, quantity: line.quantity);
      final oldRes = line.reservation;
      line.reservation = reservation;
      items.refresh();
      _analytics?.logEvent('reservation_refreshed', {
        'deal_id': dealId,
        'reservation_id': reservation.id,
      });
      if (oldRes != null) {
        _releaseSilently(oldRes.id);
      }
    } on ApiException catch (e) {
      _analytics?.logEvent('reservation_refresh_failed', {
        'deal_id': dealId,
        'status': e.statusCode,
      });
      _notify(
        'Still no luck',
        e.statusCode == 409
            ? 'That deal sold out. Try removing it from the bag.'
            : e.message,
      );
    } finally {
      reservingDealIds.remove(dealId);
    }
  }

  // ----------------------------------------------------------------- helpers

  bool isReserving(int dealId) => reservingDealIds.contains(dealId);

  bool isReservationExpired(CartItemModel item) {
    final res = item.reservation;
    if (res == null) return false;
    final now = _ticker?.now.value ?? DateTime.now().toUtc();
    return !res.expiresAt.isAfter(now);
  }

  Duration? holdRemaining(CartItemModel item) {
    final res = item.reservation;
    if (res == null) return null;
    final now = _ticker?.now.value ?? DateTime.now().toUtc();
    return res.expiresAt.difference(now);
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  void _notify(String title, String message) {
    if (Get.context == null) return;
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.black87,
      colorText: Colors.white,
    );
  }

  // ----------------------------------------------------- F-1 (flash prune)

  void _pruneExpiredFlashSales(DateTime now) {
    final expired = items
        .where((i) =>
            i.deal.flashSaleEndsAt != null &&
            !i.deal.flashSaleEndsAt!.isAfter(now))
        .toList(growable: false);
    if (expired.isEmpty) return;
    items.removeWhere((i) => expired.any((e) => e.deal.id == i.deal.id));
    _recount();
    for (final item in expired) {
      LogService.log('cart: removed expired flash deal ${item.deal.id}');
      _analytics?.logEvent('flash_deal_removed_from_bag', {
        'deal_id': item.deal.id,
        'quantity': item.quantity,
      });
      final resId = item.reservation?.id;
      if (resId != null) _releaseSilently(resId);
      _notifyFlashRemoved(item);
    }
  }

  void _notifyFlashRemoved(CartItemModel item) {
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
