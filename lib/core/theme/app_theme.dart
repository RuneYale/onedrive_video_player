import 'package:flutter/material.dart';

import 'smartisan_kit.dart';

/// The app's theme, built entirely from the Smartisan OS kit.
///
/// One accent colour for the whole app: every accent-coloured element
/// (buttons, switches, sliders, selected rows, links) is derived from it, so a
/// screen never mixes two highlight colours.
abstract final class AppTheme {
  /// The one accent of this app — Smartisan blue.
  static Color get accent => SmartisanAccent.blue.color;

  static ThemeData light() =>
      SmartisanMaterialTheme.build(isDark: false, accent: accent);

  static ThemeData dark() =>
      SmartisanMaterialTheme.build(isDark: true, accent: accent);

  /// Tabular (monospaced) figures so durations, file sizes and the device
  /// sign-in code don't jitter as they tick.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

  /// Near-black used behind video (never pure black).
  static const Color playerSurface = Color(0xFF0B0B0F);
}
