import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/deal/deal_details_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Deterministic DealRepo — fetchById returns a Completer keyed by id so the
/// test controls when the fetch resolves. Records calls for assertions.
class _FakeDealRepo extends DealRepo {
  _FakeDealRepo() : super(api: FakeApiService());

  final Map<int, List<Completer<DealModel>>> _pending = {};
  final List<int> fetchByIdCalls = [];

  @override
  Future<DealModel> fetchById(int id) {
    fetchByIdCalls.add(id);
    final c = Completer<DealModel>();
    _pending.putIfAbsent(id, () => []).add(c);
    return c.future;
  }

  void resolve(int id, DealModel deal) =>
      _pending[id]!.removeAt(0).complete(deal);

  void resolveError(int id, Object error) =>
      _pending[id]!.removeAt(0).completeError(error);
}

DealModel _deal(int id) => DealModel(
      id: id,
      name: 'Deal $id',
      description: '',
      imageUrl: '',
      originalPrice: 100,
      price: 50,
      currencyCode: 'THB',
      quantityLeft: 3,
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

DealDetailsController _build(
  _FakeDealRepo repo, {
  Object? arguments,
  Map<String, String?> parameters = const {},
}) =>
    DealDetailsController(
      dealRepo: repo,
      cartService: CartService(),
      analytics: AnalyticsService(),
      argumentsReader: () => arguments,
      parametersReader: () => parameters,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('feed / flash-rail entry — arguments carries the DealModel', () {
    late _FakeDealRepo repo;
    late DealDetailsController controller;
    final passed = _deal(42);

    setUp(() {
      repo = _FakeDealRepo();
      controller = _build(
        repo,
        arguments: passed,
        parameters: const {'source': 'home'},
      );
      controller.onInit();
    });

    tearDown(() => controller.onClose());

    test('adopts the passed model synchronously — no network call', () {
      expect(controller.deal, same(passed));
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.canAddToCart, isTrue);
      expect(repo.fetchByIdCalls, isEmpty);
    });

    test('quantityLeft mirrors the passed model up-front', () {
      expect(controller.quantityLeft, 3);
    });
  });

  group('deep link entry — arguments is null, id in query params', () {
    late _FakeDealRepo repo;
    late DealDetailsController controller;

    setUp(() {
      repo = _FakeDealRepo();
      controller = _build(
        repo,
        arguments: null,
        parameters: const {'id': '42', 'source': 'push'},
      );
      controller.onInit();
    });

    tearDown(() => controller.onClose());

    test('starts in loading state and fires exactly one fetch by id', () {
      expect(controller.deal, isNull);
      expect(controller.isLoading, isTrue);
      expect(controller.errorMessage, isNull);
      expect(controller.canAddToCart, isFalse);
      expect(repo.fetchByIdCalls, [42]);
    });

    test('resolves into a loaded state that mirrors the fetched deal',
        () async {
      final fetched = _deal(42);
      repo.resolve(42, fetched);
      await Future<void>.value(); // let the async .then run

      expect(controller.deal, same(fetched));
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.canAddToCart, isTrue);
      expect(controller.quantityLeft, 3);
    });

    test('a failing fetch surfaces an error and lets retry succeed',
        () async {
      repo.resolveError(42, Exception('boom'));
      await Future<void>.value();

      expect(controller.deal, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNotNull);
      expect(controller.canAddToCart, isFalse);

      // Retry re-fires and success flow lands the deal.
      final retryFuture = controller.retry();
      expect(controller.isLoading, isTrue);
      repo.resolve(42, _deal(42));
      await retryFuture;

      expect(controller.deal, isNotNull);
      expect(controller.errorMessage, isNull);
      expect(controller.canAddToCart, isTrue);
      expect(repo.fetchByIdCalls, [42, 42]);
    });
  });

  group('malformed link — arguments null and id unparseable', () {
    late _FakeDealRepo repo;
    late DealDetailsController controller;

    setUp(() {
      repo = _FakeDealRepo();
      controller = _build(
        repo,
        arguments: null,
        parameters: const {'id': 'not-a-number', 'source': 'push'},
      );
      controller.onInit();
    });

    tearDown(() => controller.onClose());

    test('lands in error state and does not touch the network', () {
      expect(controller.deal, isNull);
      expect(controller.errorMessage, isNotNull);
      expect(controller.isLoading, isFalse);
      expect(repo.fetchByIdCalls, isEmpty);
    });
  });
}
