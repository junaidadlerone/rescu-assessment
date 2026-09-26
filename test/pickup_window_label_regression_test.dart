import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

/// This file uses only the pre-existing public API — so it compiles against
/// both the pre-fix and post-fix versions of [PickupWindowModel]. It's the
/// regression witness for RES-106's most user-visible symptom: a Bangkok
/// bakery open 06:00–09:30 was showing "23:00 – 02:30" in the UI.
///
/// Pre-fix: fails with `Expected: '06:00 – 09:30' Actual: '23:00 – 02:30'`.
/// Post-fix: passes.
///
/// The full clock-injected test suite lives in `pickup_window_test.dart`.
void main() {
  test('label — ticket-example bakery formats in Bangkok wall clock', () {
    final bakery = PickupWindowModel(
      start: DateTime.utc(2026, 1, 15, 23, 0),
      end: DateTime.utc(2026, 1, 16, 2, 30),
    );
    expect(bakery.label, '06:00 – 09:30');
  });
}
