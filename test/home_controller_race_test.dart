import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';
import 'package:rescu/model/pickup_window_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/fake_api_service.dart';

// Deterministic DealRepo: fetchDeals returns a Completer keyed by page number
// so the test controls the completion order and never relies on real timing.
class _FakeDealRepo extends DealRepo {
  _FakeDealRepo() : super(api: FakeApiService());

  // FIFO queue per page — two overlapping refreshes both fetch page 1, so we
  // need distinct completers for each call.
  final Map<int, List<Completer<PagedResponseModel<DealModel>>>> _pending = {};
  int totalPages = 3;

  @override
  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) {
    final c = Completer<PagedResponseModel<DealModel>>();
    _pending.putIfAbsent(page, () => []).add(c);
    return c.future;
  }

  void resolve(int page, {int itemCount = 20}) => _resolveAt(page, 0, itemCount);

  // Resolves the Nth in-flight request for the given page. Lets tests force
  // "older request wins the race" by resolving it AFTER a newer one.
  void resolveAt(int page, int index, {int itemCount = 20}) =>
      _resolveAt(page, index, itemCount);

  void _resolveAt(int page, int index, int itemCount) {
    final items = List.generate(itemCount, (i) => _deal(page * 1000 + i));
    _pending[page]!.removeAt(index).complete(
          PagedResponseModel(items: items, page: page, totalPages: totalPages),
        );
  }
}

DealModel _deal(int id) => DealModel(
      id: id,
      name: 'Deal $id',
      description: '',
      imageUrl: '',
      originalPrice: 100,
      price: 50,
      currencyCode: 'THB',
      quantityLeft: 1,
      storeId: 1,
      storeName: 'Store',
      storeAddress: '',
      lat: 0,
      lng: 0,
      rating: null,
      tags: const [],
      pickupWindow: PickupWindowModel(
        start: DateTime.now().add(const Duration(hours: 1)),
        end: DateTime.now().add(const Duration(hours: 2)),
      ),
      flashSaleEndsAt: null,
    );

void main() {
  // pull_to_refresh's RefreshController requires the widgets binding to be
  // initialised before any controller instance is constructed.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeController pagination race', () {
    late _FakeDealRepo repo;
    late HomeController controller;

    setUp(() {
      repo = _FakeDealRepo();
      controller = HomeController(dealRepo: repo);
      // Seed page 1 the same way a real _initialLoad would, so hasMore is true
      // when the race scenarios start.
      controller.refreshDeals();
      repo.resolve(1);
    });

    tearDown(() => controller.onClose());

    test(
        'refresh during in-flight loadMore drops the stale page-2 (page-1 wins first)',
        () async {
      // loadMore starts, page 2 in flight.
      final loadMoreFuture = controller.loadMore();
      // While page 2 is pending, the user pulls to refresh.
      final refreshFuture = controller.refreshDeals();
      // Refresh's page 1 completes first.
      repo.resolve(1);
      await refreshFuture;
      // Then the stale page 2 from the pre-refresh loadMore lands.
      repo.resolve(2);
      await loadMoreFuture;

      // Deals should be page 1 only. The pre-refresh loadMore was superseded.
      expect(controller.deals.length, 20);
      // hasMore should reflect _page == 1 (private, but visible via getter).
      expect(controller.hasMore, isTrue);
    });

    test(
        'refresh during in-flight loadMore drops the stale page-2 (page-2 wins first)',
        () async {
      final loadMoreFuture = controller.loadMore();
      final refreshFuture = controller.refreshDeals();
      // Stale page 2 completes before refresh's page 1 — the classic ordering
      // that produced duplicates or grow-then-shrink in production.
      repo.resolve(2);
      await loadMoreFuture;
      repo.resolve(1);
      await refreshFuture;

      // Both orderings must converge to the same state: only page 1 in the list.
      expect(controller.deals.length, 20);
      expect(controller.hasMore, isTrue);
    });

    test('two rapid refreshes: stale older result loses when it lands late',
        () async {
      final first = controller.refreshDeals();
      final second = controller.refreshDeals();

      // Newer refresh resolves FIRST with 15 items — this is the correct
      // answer the user should see.
      repo.resolveAt(1, 1, itemCount: 15);
      await second;
      // Then the older refresh lands late with 20 items. On the buggy code
      // this assignAll would overwrite the newer result. The epoch guard
      // must drop it.
      repo.resolveAt(1, 0, itemCount: 20);
      await first;

      expect(controller.deals.length, 15);
    });

    test(
        'loadMore that succeeds without a competing refresh advances the page cleanly',
        () async {
      final loadMoreFuture = controller.loadMore();
      repo.resolve(2);
      await loadMoreFuture;

      expect(controller.deals.length, 40);
      expect(controller.hasMore, isTrue); // totalPages = 3
    });
  });
}
