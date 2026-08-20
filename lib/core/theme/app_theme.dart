import 'package:fluent_ui/fluent_ui.dart';

/// Cohesive visual language for OneDrive Video Player — Fluent (WinUI) edition.
///
/// Design principles (carried over from the Material redesign audit):
/// * Neutral cool-gray surfaces as the base — no blue-tint-everywhere "AI"
///   look. The bulk of the UI is calm and neutral.
/// * A single, considered blue accent, applied sparingly (CTAs, active states,
///   folder icons, progress).
/// * Off-black dark surfaces (never pure `#000000`) for a calmer, premium feel.
/// * Windows 11 type ramp via [FluentThemeData.typography]. Tabular figures
///   are applied inline on data widgets (durations, sizes, codes) via
///   [AppTheme.tabularFigures].
class AppTheme {
  const AppTheme._();

  // --- Single accent ------------------------------------------------------
  static const Color _accentLight = Color(0xFF1F5BD8);
  static const Color _accentDark = Color(0xFF7AA6FF);

  static FluentThemeData light() => _build(Brightness.light);
  static FluentThemeData dark() => _build(Brightness.dark);

  static FluentThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;

    return FluentThemeData(
      brightness: brightness,
      accentColor: (isDark ? _accentDark : _accentLight).toAccentColor(),
      scaffoldBackgroundColor: colors.surface,
      cardColor: colors.surfaceContainer,
      menuColor: colors.surfaceContainerHigh,
      dialogTheme: ContentDialogThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: kElevationToShadow[8],
        ),
      ),
      navigationPaneTheme: NavigationPaneThemeData(
        backgroundColor: isDark ? const Color(0xFF12141A) : const Color(0xFFF3F4F8),
        highlightColor: colors.accent.withValues(alpha: 0.10),
      ),
      iconTheme: IconThemeData(size: 20, color: colors.onSurfaceVariant),
      dividerTheme: DividerThemeData(
        decoration: BoxDecoration(color: colors.outlineVariant),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(color: colors.onSurface, fontSize: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: kElevationToShadow[4],
        ),
      ),
    );
  }

  /// Tabular (monospaced) figures for stable numeric columns: durations, file
  /// sizes, and the device sign-in code. Apply via
  /// `style: TextStyle(fontFeatures: AppTheme.tabularFigures)`.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

  /// Near-black used for the immersive player surface (not pure black).
  static const Color playerSurface = Color(0xFF0B0B0F);
}

/// Semantic colors that have no direct counterpart in [FluentThemeData].
///
/// Fluent's own widgets are themed through [FluentThemeData]; these tokens are
/// for app-level decorations (custom cards, badges, placeholders) that used to
/// read from Material's `ColorScheme`.
class AppColors {
  const AppColors._({
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.error,
  });

  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color error;

  static const AppColors light = AppColors._(
    accent: Color(0xFF1F5BD8),
    onAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFE2EAFB),
    onAccentContainer: Color(0xFF0B2A66),
    surface: Color(0xFFFBFBFD),
    surfaceContainer: Color(0xFFF2F3F7),
    surfaceContainerHigh: Color(0xFFE9EBF1),
    onSurface: Color(0xFF1A1C22),
    onSurfaceVariant: Color(0xFF5C6170),
    outline: Color(0xFFD7DAE1),
    outlineVariant: Color(0xFFE7E9EE),
    error: Color(0xFFB3261E),
  );

  static const AppColors dark = AppColors._(
    accent: Color(0xFF7AA6FF),
    onAccent: Color(0xFF06122B),
    accentContainer: Color(0xFF1A2A52),
    onAccentContainer: Color(0xFFBFD2FF),
    surface: Color(0xFF0E0F13),
    surfaceContainer: Color(0xFF16181F),
    surfaceContainerHigh: Color(0xFF1D2029),
    onSurface: Color(0xFFE7E9EF),
    onSurfaceVariant: Color(0xFF9AA0AD),
    outline: Color(0xFF2B2F3A),
    outlineVariant: Color(0xFF23262F),
    error: Color(0xFFF2B8B5),
  );
}

/// Quick access to the app's semantic colors: `context.colors.accent`.
extension AppColorsContext on BuildContext {
  AppColors get colors => FluentTheme.of(this).brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
}
