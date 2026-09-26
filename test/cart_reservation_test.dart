import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/model/reservation_model.dart';
import 'package:rescu/repository/order_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/countdown_ticker.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Fully controllable OrderRepo — each reserve returns a Completer we
/// resolve in the test, so we can assert the optimistic insert appears
/// BEFORE the network round-trip lands.
class _FakeOrderRepo extends OrderRepo {
  _FakeOrderRepo({required this.currentTime}) : super(api: FakeApiService());

  /// Anchors reservation TTLs to the test's simulated "now" (the ticker)
  /// rather than real wall-clock — otherwise a reservation created "now"
  /// with a 30s TTL would sit millions of seconds in the past relative to
  /// the ticker's simulated 2026 time and every expiry test would fail.
  DateTime Function() currentTime;
  final Map<int, List<Completer<ReservationModel>>> _pending = {};
  final List<String> releaseCalls = [];
  int _seq = 0;

  @override
  Future<ReservationModel> reserve(int dealId, {int quantity = 1}) {
    final c = Completer<ReservationModel>();
    _pending.putIfAbsent(dealId, () => []).add(c);
    return c.future;
  }

  ReservationModel resolveWithSuccess(int dealId,
      {int quantity = 1, Duration ttl = const Duration(minutes: 5)}) {
    _seq++;
    final r = ReservationModel(
      id: 'res_$_seq',
      dealId: dealId,
      quantity: quantity,
      expiresAt: currentTime().add(ttl),
    );
    _pending[dealId]!.removeAt(0).complete(r);
    return r;
  }

  void resolveWithFailure(int dealId,
      {int statusCode = 409, String message = 'sold out'}) {
    _pending[dealId]!
        .removeAt(0)
        .completeError(ApiException(message, statusCode: statusCode));
  }

  @override
  Future<void> releaseReservation(String reservationId) async {
    releaseCalls.add(reservationId);
  }
}

DealModel _deal(int id, {int quantityLeft = 5}) => DealModel(
      id: id,
      name: 'Deal $id',
      description: '',
      imageUrl: '',
      originalPrice: 100,
      price: 50,
      currencyCode: 'THB',
      quantityLeft: quantityLeft,
      storeId: 1,
      storeName: 'Store',
      storeAddress: '',
      lat: 0,
      lng: 0,
      rating: null,
      tags: const [],
      pickupWindow: PickupWindowModel(
        start: DateTime.utc(2026, 1, 1, 10, 0),
        end: DateTime.utc(2026, 1, 1, 12, 0),
      ),
      flashSaleEndsAt: null,
    );

void main() {
  late CountdownTicker ticker;
  late _FakeOrderRepo repo;
  late CartService cart;

  setUp(() {
    Get.reset();
    ticker = CountdownTicker(
      nowFactory: () => DateTime.utc(2026, 1, 1, 12, 0),
    );
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0));
    Get.put<CountdownTicker>(ticker);
    Get.put<AnalyticsService>(AnalyticsService());
    repo = _FakeOrderRepo(currentTime: () => ticker.now.value);
    Get.put<OrderRepo>(repo);
    cart = CartService();
    cart.onInit();
  });

  tearDown(() {
    cart.onClose();
    Get.reset();
  });

  group('optimistic add', () {
    test('inserts the line before reserve returns', () async {
      final addFuture = cart.add(_deal(1));
      // BEFORE we resolve the reserve, the line should already be visible
      // and marked as reserving.
      expect(cart.items.map((i) => i.deal.id), [1]);
      expect(cart.isReserving(1), isTrue);
      expect(cart.items.single.reservation, isNull);

      final res = repo.resolveWithSuccess(1);
      await addFuture;

      expect(cart.isReserving(1), isFalse);
      expect(cart.items.single.reservation, isNotNull);
      expect(cart.items.single.reservation!.id, res.id);
    });

    test('409 failure rolls back the optimistic insert', () async {
      final addFuture = cart.add(_deal(2));
      expect(cart.items, hasLength(1));

      repo.resolveWithFailure(2);
      await addFuture;

      expect(cart.items, isEmpty);
      expect(cart.isReserving(2), isFalse);
      expect(cart.itemCount.value, 0);
    });

    test('user removes optimistic line before reserve returns — orphan hold released',
        () async {
      final addFuture = cart.add(_deal(3));
      expect(cart.items, hasLength(1));

      // User taps remove while the reserve is still in flight.
      cart.remove(3);
      expect(cart.items, isEmpty);

      // Reserve now returns success — the line is gone, so the reservation
      // is an orphan. It must be released so we don't hold stock the user
      // no longer wants.
      final res = repo.resolveWithSuccess(3);
      await addFuture;
      // Flush the .catchError on the release Future.
      await Future<void>.value();

      expect(repo.releaseCalls, contains(res.id));
    });
  });

  group('removals release the hold', () {
    test('remove() releases the reservation', () async {
      final addFuture = cart.add(_deal(4));
      final res = repo.resolveWithSuccess(4);
      await addFuture;

      cart.remove(4);
      await Future<void>.value();
      expect(repo.releaseCalls, contains(res.id));
    });

    test('decrement to zero releases the reservation', () async {
      final addFuture = cart.add(_deal(5));
      final res = repo.resolveWithSuccess(5);
      await addFuture;

      cart.decrement(5); // quantity was 1 → 0 → line removed
      await Future<void>.value();
      expect(cart.items, isEmpty);
      expect(repo.releaseCalls, contains(res.id));
    });

    test('clear() releases every reservation', () async {
      final f1 = cart.add(_deal(6));
      final r1 = repo.resolveWithSuccess(6);
      await f1;
      final f2 = cart.add(_deal(7));
      final r2 = repo.resolveWithSuccess(7);
      await f2;

      cart.clear();
      await Future<void>.value();
      expect(cart.items, isEmpty);
      expect(repo.releaseCalls, containsAll([r1.id, r2.id]));
    });

    test('clearAfterCheckout does NOT release — the server consumed them',
        () async {
      final f = cart.add(_deal(8));
      repo.resolveWithSuccess(8);
      await f;

      cart.clearAfterCheckout();
      await Future<void>.value();
      expect(cart.items, isEmpty);
      expect(repo.releaseCalls, isEmpty);
    });
  });

  group('expiry / refresh', () {
    test('isReservationExpired flips true past the reservation TTL',
        () async {
      // now = 2026-01-01 12:00; reservation TTL 30s (test-only short window
      // via ReservationModel injected below via resolveWithSuccess ttl).
      final f = cart.add(_deal(9));
      repo.resolveWithSuccess(9, ttl: const Duration(seconds: 30));
      await f;

      expect(cart.isReservationExpired(cart.items.single), isFalse);
      ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 29));
      expect(cart.isReservationExpired(cart.items.single), isFalse);
      ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 31));
      expect(cart.isReservationExpired(cart.items.single), isTrue);
    });

    test('holdRemaining decrements on tick', () async {
      final f = cart.add(_deal(10));
      repo.resolveWithSuccess(10, ttl: const Duration(seconds: 30));
      await f;

      expect(cart.holdRemaining(cart.items.single),
          const Duration(seconds: 30));
      ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 10));
      expect(cart.holdRemaining(cart.items.single),
          const Duration(seconds: 20));
    });

    test('refreshHold replaces the reservation on success and releases the old one',
        () async {
      final f = cart.add(_deal(11));
      final oldRes =
          repo.resolveWithSuccess(11, ttl: const Duration(seconds: 30));
      await f;

      final refreshFuture = cart.refreshHold(11);
      expect(cart.isReserving(11), isTrue);
      final newRes = repo.resolveWithSuccess(11);
      await refreshFuture;
      await Future<void>.value();

      expect(cart.items.single.reservation!.id, newRes.id);
      expect(repo.releaseCalls, contains(oldRes.id));
    });

    test('refreshHold failure leaves the expired line intact for another try',
        () async {
      final f = cart.add(_deal(12));
      repo.resolveWithSuccess(12, ttl: const Duration(seconds: 5));
      await f;
      ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 10)); // now expired

      final refreshFuture = cart.refreshHold(12);
      repo.resolveWithFailure(12);
      await refreshFuture;

      // Line is still in the bag — user can try again.
      expect(cart.items.map((i) => i.deal.id), [12]);
      expect(cart.isReservationExpired(cart.items.single), isTrue);
      expect(cart.isReserving(12), isFalse);
    });
  });
}
