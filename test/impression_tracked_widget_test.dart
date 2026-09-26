import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/impression_tracked.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';
import 'package:rescu/service/impression_tracker.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _RecordingApi extends FakeApiService {
  final List<List<Map<String, dynamic>>> flushed = [];

  @override
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    flushed.add(List.of(events));
  }
}

class _NavigatorHost extends StatelessWidget {
  final Widget child;
  const _NavigatorHost({required this.child});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: child));
}

void main() {
  late ImpressionTracker tracker;
  late AnalyticsService analytics;

  setUp(() {
    // Test-only: make VisibilityDetector fire immediately instead of
    // debouncing ~500ms. Otherwise tester.pump can't catch the transitions.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    Get.reset();
    analytics = AnalyticsService();
    Get.put<AnalyticsService>(analytics);
    Get.put<FakeApiService>(_RecordingApi());
    tracker = ImpressionTracker();
    Get.put<ImpressionTracker>(tracker);
  });

  tearDown(Get.reset);

  testWidgets('does NOT fire before 1 continuous second of ≥50% visibility',
      (tester) async {
    await tester.pumpWidget(_NavigatorHost(
      child: ImpressionTracked(
        dealId: 1,
        source: 'home',
        position: 0,
        child: Container(
          width: 300,
          height: 300,
          color: const Color(0xFFFF0000),
        ),
      ),
    ));

    // Immediately visible, but only for a fraction of a second.
    await tester.pump(const Duration(milliseconds: 500));
    expect(tracker.seenIds, isEmpty);
  });

  testWidgets('fires after 1 continuous second of ≥50% visibility',
      (tester) async {
    await tester.pumpWidget(_NavigatorHost(
      child: ImpressionTracked(
        dealId: 2,
        source: 'home',
        position: 5,
        child: Container(
            width: 300, height: 300, color: const Color(0xFF00FF00)),
      ),
    ));

    await tester.pump(const Duration(seconds: 1));
    expect(tracker.seenIds, {2});
    final event = analytics.events.single;
    expect(event.name, 'deal_impression');
    expect(event.properties['deal_id'], 2);
    expect(event.properties['source'], 'home');
    expect(event.properties['position'], 5);
    // Cancel the pending 15s flush timer so flutter_test doesn't fail
    // teardown with "A Timer is still pending" (same assertion pattern as
    // the RES-102 lifecycle test).
    tracker.onClose();
  });

  testWidgets(
      'scrolling past a card in under 1s must not fire — dwell timer cancels',
      (tester) async {
    // Start visible.
    await tester.pumpWidget(_NavigatorHost(
      child: ImpressionTracked(
        dealId: 3,
        source: 'home',
        position: 0,
        child: Container(
            width: 300, height: 300, color: const Color(0xFF0000FF)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    // Replace with something else that hides the tracked widget entirely.
    await tester.pumpWidget(_NavigatorHost(
      child: const SizedBox.shrink(),
    ));
    // Give the visibility notifier a frame to observe the removal.
    await tester.pump(const Duration(milliseconds: 100));
    // Now let plenty of time elapse — nothing should fire because the
    // timer was cancelled when visibility dropped below the threshold.
    await tester.pump(const Duration(seconds: 5));

    expect(tracker.seenIds, isEmpty);
  });

  testWidgets('same deal on two surfaces logs once, not twice',
      (tester) async {
    Widget wrap(String source) => ImpressionTracked(
          dealId: 99,
          source: source,
          position: 0,
          child: Container(
              width: 300, height: 100, color: const Color(0xFF888888)),
        );

    await tester.pumpWidget(_NavigatorHost(
      child: Column(
        children: [wrap('home'), wrap('search')],
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    // Both widgets tick, both call recordImpression — session dedup
    // collapses them into a single logged event.
    expect(tracker.seenIds, {99});
    expect(analytics.events.length, 1);
    tracker.onClose();
  });
}
