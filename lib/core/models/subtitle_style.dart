import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-customizable appearance for on-screen subtitles.
///
/// Persisted locally so choices survive app restarts. Applied to media_kit's
/// [SubtitleViewConfiguration] on the [Video] widget.
class SubtitleStyle {
  const SubtitleStyle({
    this.fontSize = 30.0,
    this.fontWeight = FontWeight.w600,
    this.color = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0xB3000000),
    this.showBackground = true,
    this.outlineEnabled = false,
    this.outlineColor = const Color(0xFF000000),
    this.outlineWidth = 2.0,
    this.lineHeight = 1.4,
  });

  /// Subtitle font size in logical pixels.
  final double fontSize;

  /// Subtitle text weight.
  final FontWeight fontWeight;

  /// Subtitle text color.
  final Color color;

  /// Subtitle background color (used when [showBackground] is true).
  final Color backgroundColor;

  /// Whether a semi-transparent background is drawn behind the text.
  final bool showBackground;

  /// Whether a text outline (stroke) is drawn for readability over bright video.
  final bool outlineEnabled;

  /// Outline color.
  final Color outlineColor;

  /// Outline width in logical pixels.
  final double outlineWidth;

  /// Line height multiplier for multi-line subtitles.
  final double lineHeight;

  SubtitleStyle copyWith({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    Color? backgroundColor,
    bool? showBackground,
    bool? outlineEnabled,
    Color? outlineColor,
    double? outlineWidth,
    double? lineHeight,
  }) =>
      SubtitleStyle(
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        color: color ?? this.color,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        showBackground: showBackground ?? this.showBackground,
        outlineEnabled: outlineEnabled ?? this.outlineEnabled,
        outlineColor: outlineColor ?? this.outlineColor,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        lineHeight: lineHeight ?? this.lineHeight,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'fontSize': fontSize,
        'fontWeight': fontWeight.value,
        'color': color.toARGB32(),
        'backgroundColor': backgroundColor.toARGB32(),
        'showBackground': showBackground,
        'outlineEnabled': outlineEnabled,
        'outlineColor': outlineColor.toARGB32(),
        'outlineWidth': outlineWidth,
        'lineHeight': lineHeight,
      };

  factory SubtitleStyle.fromMap(Map<String, dynamic> map) {
    // Map the stored int back to a FontWeight. FontWeight.value is the numeric
    // weight (400/500/600/700...); we find the closest standard weight.
    final wValue = (map['fontWeight'] as int?) ?? 600;
    final weights = [
      FontWeight.w100, FontWeight.w200, FontWeight.w300, FontWeight.w400,
      FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800,
      FontWeight.w900,
    ];
    final fontWeight = weights.reduce((a, b) =>
        (a.value - wValue).abs() <= (b.value - wValue).abs() ? a : b);
    return SubtitleStyle(
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 30.0,
        fontWeight: fontWeight,
        color: Color(map['color'] as int? ?? 0xFFFFFFFF),
        backgroundColor:
            Color(map['backgroundColor'] as int? ?? 0xB3000000),
        showBackground: map['showBackground'] as bool? ?? true,
        outlineEnabled: map['outlineEnabled'] as bool? ?? false,
        outlineColor: Color(map['outlineColor'] as int? ?? 0xFF000000),
        outlineWidth: (map['outlineWidth'] as num?)?.toDouble() ?? 2.0,
        lineHeight: (map['lineHeight'] as num?)?.toDouble() ?? 1.4,
      );
  }

  @override
  String toString() => 'SubtitleStyle($fontSize, $fontWeight, $color)';
}

/// Persists the user's [SubtitleStyle] in SharedPreferences.
class SubtitleStyleService {
  const SubtitleStyleService();

  static const _key = 'odvp_subtitle_style';

  Future<SubtitleStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const SubtitleStyle();
    try {
      return SubtitleStyle.fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SubtitleStyle();
    }
  }

  Future<void> save(SubtitleStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(style.toMap()));
  }
}
