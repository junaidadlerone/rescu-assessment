import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/countdown_ticker.dart';

/// Small mm:ss badge that ticks every second and flips to an "Expired" chip
/// once [endsAt] passes.
///
/// Uses the app-wide [CountdownTicker] — one timer for the whole app, not
/// one per widget. The `Obx` here is deliberately scoped to the `Text` and
/// nothing above it, so on each tick only the label rebuilds. Even with 100
/// visible countdowns the per-frame work is a hundred Text rebuilds, not a
/// hundred widget subtrees.
///
/// Two visual variants — a filled red pill for a flash rail / details use
/// (`emphasis: FlashCountdownEmphasis.high`) and a subtle inline chip for
/// feed cards (`FlashCountdownEmphasis.low`). Consumers pick; the widget
/// otherwise renders identically across surfaces.
class FlashCountdown extends StatelessWidget {
  final DateTime endsAt;
  final FlashCountdownEmphasis emphasis;

  const FlashCountdown({
    super.key,
    required this.endsAt,
    this.emphasis = FlashCountdownEmphasis.high,
  });

  @override
  Widget build(BuildContext context) {
    final ticker = Get.find<CountdownTicker>();
    return Obx(() {
      final remaining = endsAt.difference(ticker.now.value);
      final expired = remaining.isNegative || remaining == Duration.zero;
      return _Chip(
        emphasis: emphasis,
        expired: expired,
        label: expired ? 'Expired' : _mmss(remaining),
      );
    });
  }
}

enum FlashCountdownEmphasis { high, low }

class _Chip extends StatelessWidget {
  final FlashCountdownEmphasis emphasis;
  final bool expired;
  final String label;

  const _Chip({
    required this.emphasis,
    required this.expired,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme(emphasis, expired);
    return Container(
      padding: theme.padding,
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(6),
        border: theme.border,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: emphasis == FlashCountdownEmphasis.high ? 12 : 11,
          fontWeight: FontWeight.w600,
          color: theme.foreground,
        ),
      ),
    );
  }

  static _ChipTheme _resolveTheme(FlashCountdownEmphasis e, bool expired) {
    if (expired) {
      return const _ChipTheme(
        background: Color(0xFFEDEDED),
        foreground: Color(0xFF666666),
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        border: null,
      );
    }
    switch (e) {
      case FlashCountdownEmphasis.high:
        return _ChipTheme(
          background: Colors.red.shade600,
          foreground: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: null,
        );
      case FlashCountdownEmphasis.low:
        return _ChipTheme(
          background: Colors.red.shade50,
          foreground: Colors.red.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          border: null,
        );
    }
  }
}

class _ChipTheme {
  final Color background;
  final Color foreground;
  final EdgeInsets padding;
  final BoxBorder? border;
  const _ChipTheme({
    required this.background,
    required this.foreground,
    required this.padding,
    required this.border,
  });
}

String _mmss(Duration d) {
  final total = d.inSeconds;
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
