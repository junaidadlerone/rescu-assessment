import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';

import '../util/log_service.dart';
import 'analytics_service.dart';
import 'fake_api_service.dart';

/// Records `deal_impression` analytics events.
///
/// The widget-side ([ImpressionTracked]) is responsible for the "≥50%
/// visible for 1 continuous second" gate. This service handles what is
/// still shared state and needs to survive the widget:
///
///   1. **Session dedup** — a deal is recorded exactly once per session
///      regardless of how many surfaces / positions it appears on.
///   2. **Local sink** — pushes to [AnalyticsService] so events show up on
///      the on-device Analytics debug screen for verification.
///   3. **Batched network flush** — accumulates events and calls
///      [FakeApiService.sendAnalyticsBatch] on the earlier of 10 pending
///      events or 15 seconds since the first-in-batch. Prevents one POST
///      per impression.
///
/// [_flushBatch] is the trap boundary: too aggressive and we regress
/// scroll performance with a chatty network; too lazy and the batch grows
/// unbounded. The 10-or-15s rule comes straight from the ticket.
class ImpressionTracker extends GetxService {
  static const int maxBatchSize = 10;
  static const Duration maxBatchAge = Duration(seconds: 15);

  final FakeApiService _api;
  final AnalyticsService _analytics;

  ImpressionTracker({
    FakeApiService? api,
    AnalyticsService? analytics,
  })  : _api = api ?? Get.find<FakeApiService>(),
        _analytics = analytics ?? Get.find<AnalyticsService>();

  final Set<int> _seen = <int>{};
  final List<Map<String, dynamic>> _pending = <Map<String, dynamic>>[];
  Timer? _flushTimer;

  /// Widgets call this once their dwell timer fires. Second and later calls
  /// for the same [dealId] are dropped — impressions are session-unique.
  void recordImpression({
    required int dealId,
    required String source,
    required int position,
  }) {
    if (_seen.contains(dealId)) return;
    _seen.add(dealId);

    final event = <String, dynamic>{
      'name': 'deal_impression',
      'deal_id': dealId,
      'source': source,
      'position': position,
    };

    // Push to the local sink so the Analytics debug screen shows the event
    // immediately, without waiting for the batch flush.
    _analytics.logEvent('deal_impression', {
      'deal_id': dealId,
      'source': source,
      'position': position,
    });

    _pending.add(event);

    if (_pending.length >= maxBatchSize) {
      _flushNow();
    } else {
      _flushTimer ??= Timer(maxBatchAge, _flushNow);
    }
  }

  /// Force a flush — useful on backgrounding / logout / test teardown.
  Future<void> flush() => _flushNow();

  Future<void> _flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final toSend = List<Map<String, dynamic>>.from(_pending);
    _pending.clear();
    try {
      await _api.sendAnalyticsBatch(toSend);
    } catch (e) {
      // Don't crash the app for a failed impression flush; the debug sink
      // already recorded the events for local visibility.
      LogService.error('impression batch flush failed', e);
    }
  }

  @override
  void onClose() {
    _flushTimer?.cancel();
    super.onClose();
  }

  // ---------------------------------------------------------------- test hooks

  @visibleForTesting
  int get pendingCount => _pending.length;

  @visibleForTesting
  Set<int> get seenIds => Set.unmodifiable(_seen);
}
