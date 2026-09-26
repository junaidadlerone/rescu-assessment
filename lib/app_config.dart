import 'package:flutter/material.dart';

abstract class AppConfig {
  static const appName = 'Rescu';

  static const primaryGreen = Color(0xFF2FB57C);

  /// Rescu is a single-market app serving Bangkok (Asia/Bangkok, UTC+7). Pickup
  /// windows are displayed in the store's wall-clock time — not the user's
  /// device time — because the user physically walks to the store. A user in
  /// Karachi (UTC+5) buying a bag from a Bangkok bakery that opens at 06:00
  /// local sees "06:00", not "04:00".
  ///
  /// The offset lives here, not in [PickupWindowModel], because the model is
  /// pure data — this is a product decision the app owns. When the market
  /// expands beyond a single fixed-offset zone, replace this with a per-store
  /// IANA zone (e.g. `stores/:id/timezone`) and package:timezone.
  static const marketOffset = Duration(hours: 7);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryGreen),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F7),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Color(0xFFE0E5E2)),
        ),
      );
}
