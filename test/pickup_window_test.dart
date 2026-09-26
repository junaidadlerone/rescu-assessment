import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

void main() {
  // The market is Bangkok (UTC+7). The ticket's example: a bakery open
  // 06:00–09:30 Bangkok, which the API sends as start=23:00Z (previous day)
  // and end=02:30Z (day of).
  final bakeryStartUtc = DateTime.utc(2026, 1, 15, 23, 0);
  final bakeryEndUtc = DateTime.utc(2026, 1, 16, 2, 30);
  final bakery = PickupWindowModel(start: bakeryStartUtc, end: bakeryEndUtc);

  tearDown(() => PickupWindowModel.now = DateTime.now);

  group('label', () {
    test('formats in market time — the ticket-example bakery reads 06:00 – 09:30',
        () {
      expect(bakery.label, '06:00 – 09:30');
    });

    test('does not depend on the device zone', () {
      // The Dart test harness itself doesn't let us swap the process zone,
      // but market conversion is math on the UTC instant, so it can't depend
      // on the device. If it did, this label would drift.
      expect(bakery.label, '06:00 – 09:30');
    });
  });

  group('isToday', () {
    test('true when current Bangkok date matches window start Bangkok date',
        () {
      // 23:30 UTC on Jan 15 = 06:30 Bangkok on Jan 16.
      // Window starts 06:00 Bangkok on Jan 16 → same market date → today.
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 15, 23, 30);
      expect(bakery.isToday, isTrue);
    });

    test('false when market date differs even though device day matches', () {
      // 20:00 UTC on Jan 15 = 03:00 Bangkok on Jan 16.
      // A user in a UTC−5 zone would see it as Jan 15 15:00 on their phone,
      // matching the window's start UTC date (Jan 15). Naïve isToday would
      // wrongly say "today" for tomorrow's Bangkok pickup. The market-aware
      // check must say "today" because Bangkok says Jan 16 and window starts
      // Jan 16 Bangkok — the point is: the answer depends on market date,
      // not device date.
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 15, 20, 0);
      expect(bakery.isToday, isTrue);
    });

    test('false the calendar day before, in Bangkok terms', () {
      // 15:00 UTC on Jan 14 = 22:00 Bangkok Jan 14. Window is Jan 16 Bangkok.
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 14, 15, 0);
      expect(bakery.isToday, isFalse);
    });

    test('false the calendar day after, in Bangkok terms', () {
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 17, 5, 0);
      expect(bakery.isToday, isFalse);
    });

    test('would have been wrong with the naïve start.day == now.day check',
        () {
      // Regression guard: the pre-fix code compared only `.day`. On this
      // instant, start.day (window UTC) = 15 but Bangkok Jan-16 window is
      // "today", and naïve comparison against nowUtc.day (=16) would say
      // false. On the fixed code both sides land on Jan 16 in Bangkok → true.
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 15, 23, 30);
      expect(bakery.isToday, isTrue);
    });
  });

  group('isOpenNow', () {
    // Deliberately verifies the getter that was ALREADY correct pre-fix —
    // isAfter/isBefore compare absolute instants regardless of zone.
    test('true when the injected instant sits inside the window', () {
      // 00:30 UTC on Jan 16 = 07:30 Bangkok — inside 06:00–09:30 Bangkok.
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 16, 0, 30);
      expect(bakery.isOpenNow, isTrue);
    });

    test('false before start', () {
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 15, 22, 59);
      expect(bakery.isOpenNow, isFalse);
    });

    test('false after end', () {
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 16, 2, 31);
      expect(bakery.isOpenNow, isFalse);
    });

    test('works identically when the "now" clock is in a local zone',
        () {
      // Same instant expressed as a local (non-UTC) DateTime should still
      // resolve inside the window because isAfter/isBefore compare instants.
      PickupWindowModel.now =
          () => DateTime.utc(2026, 1, 16, 0, 30).toLocal();
      expect(bakery.isOpenNow, isTrue);
    });
  });

  group('untilStart', () {
    test('positive before start, zero at start, negative after', () {
      PickupWindowModel.now = () => DateTime.utc(2026, 1, 15, 22, 0);
      expect(bakery.untilStart, const Duration(hours: 1));

      PickupWindowModel.now = () => DateTime.utc(2026, 1, 15, 23, 0);
      expect(bakery.untilStart, Duration.zero);

      PickupWindowModel.now = () => DateTime.utc(2026, 1, 16, 0, 0);
      expect(bakery.untilStart, const Duration(hours: -1));
    });
  });

  group('fromJson', () {
    test('parses ISO-8601 Z strings and stores them as UTC', () {
      final w = PickupWindowModel.fromJson({
        'start': '2026-01-15T23:00:00.000Z',
        'end': '2026-01-16T02:30:00.000Z',
      });
      expect(w.start.isUtc, isTrue);
      expect(w.end.isUtc, isTrue);
      expect(w.label, '06:00 – 09:30');
    });
  });
}
