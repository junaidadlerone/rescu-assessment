import 'package:intl/intl.dart';

import '../app_config.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings;
/// this class stores them as UTC and converts to market-local time for
/// display via [AppConfig.marketOffset]. See RES-106.
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  /// Injectable clock. Callers should not depend on `DateTime.now()` inside
  /// this class — tests replace this to make [isToday], [isOpenNow] and
  /// [untilStart] deterministic. See RES-106 write-up and design Q3.
  static DateTime Function() now = DateTime.now;

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? '').toUtc(),
      end: DateTime.parse(json['end'] as String? ?? '').toUtc(),
    );
  }

  // Wall-clock DateTime in the market's zone. Kept as an "isUtc" DateTime
  // whose numeric fields already hold market-local values, so DateFormat
  // prints those numbers verbatim without applying another zone shift.
  DateTime get _marketStart => start.add(AppConfig.marketOffset);
  DateTime get _marketEnd => end.add(AppConfig.marketOffset);

  /// Human readable label, e.g. "06:00 – 09:30". Always in market time.
  String get label =>
      '${DateFormat('HH:mm').format(_marketStart)} – ${DateFormat('HH:mm').format(_marketEnd)}';

  /// Whether pickup starts today **in the market's zone** — not the device's.
  /// A user in Karachi looking at a Bangkok bakery whose window starts at
  /// 06:00 Bangkok should see "today" if it's the same calendar day in
  /// Bangkok, regardless of what their phone's calendar says.
  bool get isToday {
    final nowMarket = now().toUtc().add(AppConfig.marketOffset);
    final startMarket = _marketStart;
    return nowMarket.year == startMarket.year &&
        nowMarket.month == startMarket.month &&
        nowMarket.day == startMarket.day;
  }

  /// Whether the store is currently accepting pickups.
  ///
  /// Correct as-is — `isAfter` / `isBefore` compare absolute instants
  /// regardless of the DateTime's declared zone. UTC `start` vs local `now`
  /// still resolves to the right instant comparison. Left untouched
  /// deliberately.
  bool get isOpenNow {
    final n = now();
    return n.isAfter(start) && n.isBefore(end);
  }

  /// Correct for the same reason as [isOpenNow] — `difference()` operates on
  /// instants. Uses the injectable clock so tests aren't wall-clock-dependent.
  Duration get untilStart => start.difference(now());
}
