import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/countdown_ticker.dart';

DealModel _deal(
  int id, {
  DateTime? flashSaleEndsAt,
  int quantityLeft = 5,
}) =>
    DealModel(
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
      flashSaleEndsAt: flashSaleEndsAt,
    );

void main() {
  late CountdownTicker ticker;
  late AnalyticsService analytics;
  late CartService cart;

  setUp(() {
    Get.reset();
    ticker = CountdownTicker(
      nowFactory: () => DateTime.utc(2026, 1, 1, 12, 0),
    );
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0));
    Get.put<CountdownTicker>(ticker);

    analytics = AnalyticsService();
    Get.put<AnalyticsService>(analytics);

    cart = CartService();
    Get.put<CartService>(cart);
    cart.onInit();
  });

  tearDown(() {
    cart.onClose();
    Get.reset();
  });

  test('non-flash items are never pruned', () {
    cart.add(_deal(1)); // no flashSaleEndsAt
    expect(cart.items.length, 1);

    ticker.tickTo(DateTime.utc(2027, 1, 1)); // way past anything
    expect(cart.items.length, 1);
  });

  test('a flash item is removed on the first tick after its endsAt', () {
    final expiring =
        _deal(42, flashSaleEndsAt: DateTime.utc(2026, 1, 1, 12, 0, 5));
    cart.add(expiring);
    expect(cart.items.length, 1);
    expect(cart.itemCount.value, 1);

    // 4 seconds later — still alive.
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 4));
    expect(cart.items.length, 1);

    // Tick past the sale end — the pruning fires and analytics records it.
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 5));
    expect(cart.items, isEmpty);
    expect(cart.itemCount.value, 0);
    expect(
      analytics.events.map((e) => e.name),
      contains('flash_deal_removed_from_bag'),
    );
    final removedEvent = analytics.events
        .firstWhere((e) => e.name == 'flash_deal_removed_from_bag');
    expect(removedEvent.properties['deal_id'], 42);
  });

  test('mixed cart — only the expired flash item goes', () {
    final expiring =
        _deal(42, flashSaleEndsAt: DateTime.utc(2026, 1, 1, 12, 0, 3));
    final alive =
        _deal(43, flashSaleEndsAt: DateTime.utc(2026, 1, 1, 13, 0));
    final regular = _deal(44);
    cart..add(expiring)..add(alive)..add(regular);
    expect(cart.itemCount.value, 3);

    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 3));
    expect(cart.items.map((i) => i.deal.id).toList(), [43, 44]);
    expect(cart.itemCount.value, 2);
  });

  test('prune fires exactly one analytics event per expiration', () {
    final expiring =
        _deal(42, flashSaleEndsAt: DateTime.utc(2026, 1, 1, 12, 0, 5));
    cart.add(expiring);

    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 5));
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 6)); // another tick
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0, 7));

    expect(
      analytics.events
          .where((e) => e.name == 'flash_deal_removed_from_bag')
          .length,
      1,
      reason: 'the deal is already gone after the first tick — no double log',
    );
  });
}
