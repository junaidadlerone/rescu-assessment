import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';
import 'package:rescu/service/impression_tracker.dart';

/// Records every sendAnalyticsBatch call for assertions. Extending
/// FakeApiService dodges its async `init()` — the tracker only calls
/// sendAnalyticsBatch, so nothing else in the parent needs to work.
class _RecordingApi extends FakeApiService {
  final List<List<Map<String, dynamic>>> flushed = [];

  @override
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    flushed.add(List.of(events));
  }
}

class _ThrowingApi extends FakeApiService {
  @override
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    throw Exception('backend on fire');
  }
}

ImpressionTracker _tracker(FakeApiService api, AnalyticsService analytics) =>
    ImpressionTracker(api: api, analytics: analytics);

void main() {
  group('session dedup', () {
    test('same deal id records at most once regardless of source/position',
        () {
      final api = _RecordingApi();
      final analytics = AnalyticsService();
      final tracker = _tracker(api, analytics);

      tracker.recordImpression(dealId: 42, source: 'home', position: 3);
      tracker.recordImpression(dealId: 42, source: 'search', position: 7);
      tracker.recordImpression(dealId: 42, source: 'flash_rail', position: 0);

      expect(tracker.seenIds, {42});
      expect(tracker.pendingCount, 1);
      expect(
        analytics.events.where((e) => e.name == 'deal_impression').length,
        1,
      );
    });

    test('different deal ids each record independently', () {
      final api = _RecordingApi();
      final tracker = _tracker(api, AnalyticsService());

      tracker.recordImpression(dealId: 1, source: 'home', position: 0);
      tracker.recordImpression(dealId: 2, source: 'home', position: 1);
      tracker.recordImpression(dealId: 3, source: 'home', position: 2);

      expect(tracker.seenIds, {1, 2, 3});
      expect(tracker.pendingCount, 3);
    });
  });

  group('batch flush triggers', () {
    test('10 pending events triggers an immediate flush', () async {
      final api = _RecordingApi();
      final tracker = _tracker(api, AnalyticsService());

      for (var i = 1; i <= 10; i++) {
        tracker.recordImpression(dealId: i, source: 'home', position: i - 1);
      }
      // Flush is fire-and-forget; give the microtask queue a tick.
      await Future<void>.value();

      expect(api.flushed, hasLength(1));
      expect(api.flushed.first, hasLength(10));
      expect(tracker.pendingCount, 0);
    });

    test('fewer than 10 events flushes after 15 seconds', () {
      fakeAsync((async) {
        final api = _RecordingApi();
        final tracker = _tracker(api, AnalyticsService());

        tracker.recordImpression(dealId: 1, source: 'home', position: 0);
        expect(api.flushed, isEmpty);

        async.elapse(const Duration(seconds: 14));
        expect(api.flushed, isEmpty);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.flushed, hasLength(1));
        expect(api.flushed.first, hasLength(1));
      });
    });

    test('the 15s clock is anchored on the FIRST unsent event, not the last',
        () {
      fakeAsync((async) {
        final api = _RecordingApi();
        final tracker = _tracker(api, AnalyticsService());

        // t=0 first event, timer armed for 15s.
        tracker.recordImpression(dealId: 1, source: 'home', position: 0);
        async.elapse(const Duration(seconds: 10));
        // t=10 second event, should NOT reset the timer.
        tracker.recordImpression(dealId: 2, source: 'home', position: 1);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        // 15s total since t=0 — should have flushed.
        expect(api.flushed, hasLength(1));
        expect(api.flushed.first.map((e) => e['deal_id']), containsAll([1, 2]));
      });
    });

    test('after a flush the next event starts a fresh 15s window', () {
      fakeAsync((async) {
        final api = _RecordingApi();
        final tracker = _tracker(api, AnalyticsService());

        tracker.recordImpression(dealId: 1, source: 'home', position: 0);
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();
        expect(api.flushed, hasLength(1));

        // Second event AFTER the flush.
        tracker.recordImpression(dealId: 2, source: 'home', position: 0);
        async.elapse(const Duration(seconds: 14));
        expect(api.flushed, hasLength(1)); // still only the first

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.flushed, hasLength(2));
      });
    });
  });

  group('robustness', () {
    test('a backend failure does not crash the tracker', () async {
      final api = _ThrowingApi();
      final tracker = _tracker(api, AnalyticsService());

      // Nothing throws.
      for (var i = 1; i <= 10; i++) {
        tracker.recordImpression(dealId: i, source: 'home', position: 0);
      }
      await Future<void>.value();
      // Pending got cleared even though the send failed — future events
      // are not blocked by a stale batch.
      expect(tracker.pendingCount, 0);
    });

    test('flush() with nothing pending is a no-op', () async {
      final api = _RecordingApi();
      final tracker = _tracker(api, AnalyticsService());
      await tracker.flush();
      expect(api.flushed, isEmpty);
    });
  });
}
