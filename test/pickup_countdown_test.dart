import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('ticks while mounted', (tester) async {
    await tester.pumpWidget(
      host(PickupCountdown(
        pickupStart: DateTime.now().add(const Duration(minutes: 2)),
      )),
    );

    expect(find.textContaining('Opens in 01:5'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Opens in 01:5'), findsOneWidget);
  });

  testWidgets('stops ticking once removed from the tree', (tester) async {
    await tester.pumpWidget(
      host(PickupCountdown(
        pickupStart: DateTime.now().add(const Duration(hours: 1)),
      )),
    );

    // Replace the subtree so the countdown's State is disposed, then let the
    // clock run past its next tick. Before the fix the periodic timer survives
    // disposal and calls setState() on a defunct State; the test binding fails
    // the test for the pending timer at teardown.
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 3));
  });
}
