import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/impression_tracker.dart';

/// Wraps a [child] with a [VisibilityDetector] and reports a
/// `deal_impression` event once the child has been ≥50% visible for a
/// continuous [dwell] (default 1s).
///
/// The dwell timer is per-widget-instance. If the card scrolls out of view
/// before the timer fires, the timer is cancelled — scrolling past a card
/// must not count, per the F-2 ticket.
///
/// The [visibilityKey] must be unique across the app (VisibilityDetector's
/// contract). The convention here is `impression-<dealId>-<source>` so the
/// same deal appearing on both the home feed and a search screen tracks
/// independently (though the tracker's session-dedup still means only the
/// first-triggered impression records).
class ImpressionTracked extends StatefulWidget {
  static const Duration defaultDwell = Duration(seconds: 1);
  static const double defaultVisibleThreshold = 0.5;

  final int dealId;
  final String source;
  final int position;
  final Widget child;
  final Duration dwell;
  final double visibleThreshold;

  const ImpressionTracked({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
    this.dwell = defaultDwell,
    this.visibleThreshold = defaultVisibleThreshold,
  });

  @override
  State<ImpressionTracked> createState() => _ImpressionTrackedState();
}

class _ImpressionTrackedState extends State<ImpressionTracked> {
  Timer? _dwell;
  bool _sufficientlyVisible = false;

  ImpressionTracker? get _tracker =>
      Get.isRegistered<ImpressionTracker>() ? Get.find<ImpressionTracker>() : null;

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // VisibilityDetector debounces its callbacks internally (~500ms) so
    // this fires on stabilised state changes, not every scroll frame.
    final now = info.visibleFraction >= widget.visibleThreshold;
    if (now == _sufficientlyVisible) return;
    _sufficientlyVisible = now;
    if (now) {
      _dwell?.cancel();
      _dwell = Timer(widget.dwell, _record);
    } else {
      _dwell?.cancel();
      _dwell = null;
    }
  }

  void _record() {
    _dwell = null;
    _tracker?.recordImpression(
      dealId: widget.dealId,
      source: widget.source,
      position: widget.position,
    );
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('impression-${widget.dealId}-${widget.source}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
