import 'package:flutter/material.dart';

/// Cohesive visual language for OneDrive Video Player.
///
/// Design principles (applied from the redesign audit):
/// * Neutral cool-gray surfaces as the base — no blue-tint-everywhere "AI"
///   look. The bulk of the UI is calm and neutral.
/// * A single, considered blue accent, applied sparingly (CTAs, active states,
///   folder icons, progress).
/// * Off-black dark surfaces (never pure `#000000`) for a calmer, premium feel.
/// * Clear typographic hierarchy: tightened display tracking, Medium/SemiBold
///   weights for hierarchy. Tabular figures are applied inline on data widgets
///   (durations, sizes, codes) via [AppTheme.tabularFigures].
class AppTheme {
  const AppTheme._();

  // --- Single accent ------------------------------------------------------
  static const Color _accentLight = Color(0xFF1F5BD8);
  static const Color _accentDark = Color(0xFF7AA6FF);

  // --- Neutral cool-gray surfaces (light) ---------------------------------
  static const Color _lightSurface = Color(0xFFFBFBFD);
  static const Color _lightContainer = Color(0xFFF2F3F7);
  static const Color _lightContainerHigh = Color(0xFFE9EBF1);
  static const Color _lightOutline = Color(0xFFD7DAE1);
  static const Color _lightOutlineVar = Color(0xFFE7E9EE);
  static const Color _lightOnSurface = Color(0xFF1A1C22);
  static const Color _lightOnSurfaceVar = Color(0xFF5C6170);

  // --- Neutral near-black surfaces (dark) ---------------------------------
  static const Color _darkSurface = Color(0xFF0E0F13);
  static const Color _darkContainer = Color(0xFF16181F);
  static const Color _darkContainerHigh = Color(0xFF1D2029);
  static const Color _darkOutline = Color(0xFF2B2F3A);
  static const Color _darkOutlineVar = Color(0xFF23262F);
  static const Color _darkOnSurface = Color(0xFFE7E9EF);
  static const Color _darkOnSurfaceVar = Color(0xFF9AA0AD);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _accentLight,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? _accentDark : _accentLight,
      onPrimary: isDark ? const Color(0xFF06122B) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF1A2A52) : const Color(0xFFE2EAFB),
      onPrimaryContainer:
          isDark ? const Color(0xFFBFD2FF) : const Color(0xFF0B2A66),
      surface: isDark ? _darkSurface : _lightSurface,
      onSurface: isDark ? _darkOnSurface : _lightOnSurface,
      surfaceContainerLowest: isDark ? _darkSurface : Colors.white,
      surfaceContainerLow: isDark ? _darkSurface : _lightSurface,
      surfaceContainer: isDark ? _darkContainer : _lightContainer,
      surfaceContainerHigh: isDark ? _darkContainerHigh : _lightContainerHigh,
      surfaceContainerHighest: isDark ? _darkContainerHigh : _lightContainerHigh,
      onSurfaceVariant: isDark ? _darkOnSurfaceVar : _lightOnSurfaceVar,
      outline: isDark ? _darkOutline : _lightOutline,
      outlineVariant: isDark ? _darkOutlineVar : _lightOutlineVar,
      inverseSurface: isDark ? const Color(0xFFE7E9EF) : const Color(0xFF1A1C22),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        toolbarHeight: 60,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: base.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(99),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: base.textTheme.labelMedium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle:
            base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        contentTextStyle: base.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
      ),
      iconTheme: IconThemeData(size: 24, color: scheme.onSurfaceVariant),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
        displayLarge: base.displayLarge
            ?.copyWith(letterSpacing: -0.5, fontWeight: FontWeight.w600),
        displayMedium: base.displayMedium
            ?.copyWith(letterSpacing: -0.5, fontWeight: FontWeight.w600),
        displaySmall: base.displaySmall
            ?.copyWith(letterSpacing: -0.25, fontWeight: FontWeight.w600),
        headlineMedium: base.headlineMedium
            ?.copyWith(letterSpacing: -0.25, fontWeight: FontWeight.w600),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        titleSmall: base.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.08),
        labelLarge: base.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        labelMedium: base.labelMedium
            ?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.08),
        labelSmall: base.labelSmall?.copyWith(letterSpacing: 0.1),
      );

  /// Tabular (monospaced) figures for stable numeric columns: durations, file
  /// sizes, and the device sign-in code. Apply via
  /// `style: TextStyle(fontFeatures: AppTheme.tabularFigures)`.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

  /// Near-black used for the immersive player surface (not pure black).
  static const Color playerSurface = Color(0xFF0B0B0F);
}