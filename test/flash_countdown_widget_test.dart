import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/flash_countdown.dart';
import 'package:rescu/service/countdown_ticker.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    // Fresh ticker per test so `.now` starts at a known value.
    Get.reset();
    final ticker = CountdownTicker(
      nowFactory: () => DateTime.utc(2026, 1, 1, 12, 0),
    );
    ticker.tickTo(DateTime.utc(2026, 1, 1, 12, 0));
    Get.put<CountdownTicker>(ticker);
  });

  tearDown(Get.reset);

  testWidgets('renders mm:ss for a future endsAt', (tester) async {
    // 03:07 in the future.
    final endsAt = DateTime.utc(2026, 1, 1, 12, 3, 7);
    await tester.pumpWidget(host(FlashCountdown(endsAt: endsAt)));
    expect(find.text('03:07'), findsOneWidget);
    expect(find.text('Expired'), findsNothing);
  });

  testWidgets('updates the label when the ticker advances — one Obx per Text',
      (tester) async {
    final endsAt = DateTime.utc(2026, 1, 1, 12, 0, 30);
    await tester.pumpWidget(host(FlashCountdown(endsAt: endsAt)));
    expect(find.text('00:30'), findsOneWidget);

    Get.find<CountdownTicker>().tickTo(DateTime.utc(2026, 1, 1, 12, 0, 25));
    await tester.pump();
    expect(find.text('00:05'), findsOneWidget);
  });

  testWidgets('flips to Expired the tick after endsAt passes', (tester) async {
    final endsAt = DateTime.utc(2026, 1, 1, 12, 0, 5);
    await tester.pumpWidget(host(FlashCountdown(endsAt: endsAt)));
    expect(find.text('00:05'), findsOneWidget);

    Get.find<CountdownTicker>().tickTo(DateTime.utc(2026, 1, 1, 12, 0, 5));
    await tester.pump();
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets(
      'high vs low emphasis renders different chrome but the same label',
      (tester) async {
    final endsAt = DateTime.utc(2026, 1, 1, 12, 1, 0);
    await tester.pumpWidget(host(Column(children: [
      FlashCountdown(endsAt: endsAt, emphasis: FlashCountdownEmphasis.high),
      FlashCountdown(endsAt: endsAt, emphasis: FlashCountdownEmphasis.low),
    ])));
    expect(find.text('01:00'), findsNWidgets(2));
  });
}
