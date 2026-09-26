import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/service/countdown_ticker.dart';

void main() {
  test('advances now once per real second from a single shared Timer',
      () {
    fakeAsync((async) {
      // Start with a fixed clock so the assertions are exact.
      var wallClock = DateTime.utc(2026, 1, 1, 12, 0);
      final ticker = CountdownTicker(nowFactory: () => wallClock);
      ticker.onInit();

      expect(ticker.now.value, DateTime.utc(2026, 1, 1, 12, 0));

      wallClock = DateTime.utc(2026, 1, 1, 12, 0, 1);
      async.elapse(const Duration(seconds: 1));
      expect(ticker.now.value, DateTime.utc(2026, 1, 1, 12, 0, 1));

      wallClock = DateTime.utc(2026, 1, 1, 12, 0, 3);
      async.elapse(const Duration(seconds: 2));
      expect(ticker.now.value, DateTime.utc(2026, 1, 1, 12, 0, 3));

      ticker.onClose();
    });
  });

  test('stops firing once closed', () {
    fakeAsync((async) {
      var wallClock = DateTime.utc(2026, 1, 1);
      final ticker = CountdownTicker(nowFactory: () => wallClock);
      ticker.onInit();
      wallClock = DateTime.utc(2026, 1, 1, 0, 0, 1);
      async.elapse(const Duration(seconds: 1));
      expect(ticker.now.value.second, 1);

      ticker.onClose();
      // Advance the wall clock after close — the timer is cancelled, so
      // `now` should stay at whatever it was on the last tick.
      wallClock = DateTime.utc(2026, 1, 1, 0, 5);
      async.elapse(const Duration(minutes: 5));
      expect(ticker.now.value.second, 1);
    });
  });
}
