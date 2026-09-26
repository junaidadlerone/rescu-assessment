import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';

/// Single app-wide 1Hz ticker.
///
/// The trap on F-1 is one `Timer.periodic` per countdown widget — with a
/// hundred flash-sale badges on screen that's a hundred timers firing every
/// second, each nudging its own widget. This service owns exactly one timer
/// for the app's lifetime, and every countdown widget observes [now]. The
/// per-second rebuild scope is therefore whatever the widget wraps in its
/// `Obx` — in this codebase, a single `Text`.
///
/// Cost of always-on: one Rx assignment per second while the app is alive.
/// With zero observers this triggers zero rebuilds; Obx only fires for
/// widgets currently in the tree. Cheaper than reference-counting subscribers
/// and starting/stopping the underlying `Timer`.
///
/// [nowFactory] is a testing seam. Production uses `DateTime.now`; tests
/// substitute a controllable clock so assertions are deterministic.
class CountdownTicker extends GetxService {
  final DateTime Function() _nowFactory;

  CountdownTicker({DateTime Function()? nowFactory})
      : _nowFactory = nowFactory ?? DateTime.now;

  late final Rx<DateTime> now = _nowFactory().obs;

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = _nowFactory();
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  /// Manual advance for tests — call after replacing [_nowFactory] via a
  /// subclass. In production the periodic timer drives this same field.
  @visibleForTesting
  void tickTo(DateTime t) {
    now.value = t;
  }
}
