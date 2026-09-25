import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/search/search_deals_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/fake_api_service.dart';

DealModel _deal(String name) => DealModel.fromJson({
      'id': name.length,
      'name': name,
      'pickupWindow': {
        'start': '2026-01-01T10:00:00.000Z',
        'end': '2026-01-01T12:00:00.000Z',
      },
    });

/// Mirrors the one behaviour of the real backend that causes RES-101: broad
/// queries are answered more slowly than specific ones, so a short query sent
/// first can land after a longer query sent later.
/// See `FakeApiService.searchDeals`: `max(0, 1200 - query.length * 280)`.
class _InvertedLatencyRepo extends DealRepo {
  _InvertedLatencyRepo() : super(api: FakeApiService());

  final List<String> requested = <String>[];

  @override
  Future<List<DealModel>> search(String query) async {
    requested.add(query);
    final ms = max(50, 1200 - query.length * 280);
    await Future<void>.delayed(Duration(milliseconds: ms));
    return [_deal(query)];
  }
}

void main() {
  late _InvertedLatencyRepo repo;
  late SearchDealsController controller;

  setUp(() {
    repo = _InvertedLatencyRepo();
    controller = SearchDealsController(dealRepo: repo)..onInit();
  });

  tearDown(() => controller.onClose());

  testWidgets('keeps the result for the query the user actually typed',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    // "s" is dispatched first and takes 920ms. "sushi" is dispatched ~350ms
    // later and takes 50ms, so it resolves long before "s" does.
    controller.onQueryChanged('s');
    await tester.pump(const Duration(milliseconds: 350));
    controller.onQueryChanged('sushi');

    // Past the debounce window and both responses.
    await tester.pump(const Duration(milliseconds: 1500));

    expect(repo.requested, ['s', 'sushi'],
        reason: 'both queries should have been dispatched, in this order');
    expect(controller.results.single.name, 'sushi',
        reason: "the late reply for 's' must not overwrite 'sushi'");
    expect(controller.isLoading.value, isFalse);
  });

  testWidgets('collapses a burst of keystrokes into one request',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    for (final q in ['s', 'su', 'sus', 'sush', 'sushi']) {
      controller.onQueryChanged(q);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 1500));

    expect(repo.requested, ['sushi'],
        reason: 'typing within the debounce window should send one request');
    expect(controller.results.single.name, 'sushi');
  });

  testWidgets('clearing the field discards a reply already in flight',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    controller.onQueryChanged('s');
    await tester.pump(const Duration(milliseconds: 400)); // request dispatched
    controller.onQueryChanged('');

    await tester.pump(const Duration(milliseconds: 1500)); // reply lands

    expect(controller.results, isEmpty,
        reason: 'an abandoned search must not repopulate a cleared field');
    expect(controller.hasSearched.value, isFalse);
    expect(controller.isLoading.value, isFalse);
  });
}
