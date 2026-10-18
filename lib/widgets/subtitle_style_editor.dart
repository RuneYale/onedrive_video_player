import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/subtitle_style.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/smartisan_kit.dart';
import '../providers/subtitle_style_provider.dart';

/// Full-screen editor for the on-screen subtitle look: a live preview on a
/// video-black plate, then grouped Smartisan cards for the text, background
/// and outline. Changes apply live (the player listens to the provider) and
/// are persisted by it on every adjustment.
class SubtitleStyleEditorPage extends ConsumerWidget {
  const SubtitleStyleEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(subtitleStyleProvider);
    final notifier = ref.read(subtitleStyleProvider.notifier);

    void update(SubtitleStyle next) => notifier.update(next);

    return Scaffold(
      backgroundColor: context.sp.page,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SAppBar(
              title: 'Subtitle appearance',
              onBack: () => unawaited(Navigator.of(context).maybePop()),
              actions: [
                SButton(
                  'Done',
                  kind: SButtonKind.small,
                  expand: false,
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 30),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _Preview(style: style),
                ),
                const SizedBox(height: 14),
                SmartisanListSection(
                  header: 'Text',
                  children: [
                    _SliderTile(
                      label: 'Size',
                      valueText: style.fontSize.toStringAsFixed(0),
                      value: style.fontSize,
                      min: 12,
                      max: 64,
                      onChanged: (v) =>
                          update(style.copyWith(fontSize: v)),
                    ),
                    _SliderTile(
                      label: 'Line height',
                      valueText: style.lineHeight.toStringAsFixed(2),
                      value: style.lineHeight,
                      min: 1,
                      max: 2.5,
                      onChanged: (v) =>
                          update(style.copyWith(lineHeight: v)),
                    ),
                    _WeightTile(
                      value: style.fontWeight,
                      onChanged: (w) =>
                          update(style.copyWith(fontWeight: w)),
                    ),
                    _ColorTile(
                      label: 'Text color',
                      color: style.color,
                      onColor: (c) => update(style.copyWith(color: c)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SmartisanListSection(
                  header: 'Background',
                  children: [
                    SmartisanTile(
                      title: const Text('Show background'),
                      trailing: SSwitch(
                        value: style.showBackground,
                        onChanged: (v) =>
                            update(style.copyWith(showBackground: v)),
                      ),
                    ),
                    if (style.showBackground)
                      _ColorTile(
                        label: 'Background color',
                        color: style.backgroundColor,
                        onColor: (c) =>
                            update(style.copyWith(backgroundColor: c)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SmartisanListSection(
                  header: 'Outline',
                  children: [
                    SmartisanTile(
                      title: const Text('Enable outline'),
                      trailing: SSwitch(
                        value: style.outlineEnabled,
                        onChanged: (v) =>
                            update(style.copyWith(outlineEnabled: v)),
                      ),
                    ),
                    if (style.outlineEnabled) ...[
                      _SliderTile(
                        label: 'Outline width',
                        valueText: style.outlineWidth.toStringAsFixed(1),
                        value: style.outlineWidth,
                        min: 0.5,
                        max: 6,
                        onChanged: (v) =>
                            update(style.copyWith(outlineWidth: v)),
                      ),
                      _ColorTile(
                        label: 'Outline color',
                        color: style.outlineColor,
                        onColor: (c) =>
                            update(style.copyWith(outlineColor: c)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                SmartisanListSection(
                  children: [
                    SmartisanTile(
                      title: const Text('Reset to defaults'),
                      showChevron: false,
                      onTap: () {
                        unawaited(notifier.reset());
                        showSToast(context, 'Subtitle style reset');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Video-black plate with the caption rendered exactly as it will appear.
class _Preview extends StatelessWidget {
  const _Preview({required this.style});

  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppTheme.playerSurface,
      borderRadius: BorderRadius.circular(SRadii.md),
      border: Border.all(color: context.sp.border, width: SHair.md),
    ),
    child: Stack(
      children: [
        Center(
          child: Icon(
            SGlyphs.film,
            size: 64,
            color: Colors.white.withValues(alpha: .06),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _StyledText(
              text: 'This is how your subtitles will look.',
              style: style,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StyledText extends StatelessWidget {
  const _StyledText({required this.text, required this.style});

  final String text;
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      color: style.color,
      height: style.lineHeight,
      background: style.showBackground
          ? (Paint()..color = style.backgroundColor)
          : null,
    );
    if (!style.outlineEnabled) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final shadows = <Shadow>[
      for (final o in const [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
        Offset(1, 1),
        Offset(-1, -1),
        Offset(1, -1),
        Offset(-1, 1),
      ])
        Shadow(
          color: style.outlineColor,
          offset: o * style.outlineWidth,
          blurRadius: 0,
        ),
    ];
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(shadows: shadows),
    );
  }
}

/// Label + value on one line, the kit's 4dp inset slider underneath.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 16, color: p.title),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 13,
                  color: p.subtitleOther,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SSlider(
            value: ((value - min) / (max - min)).clamp(0.0, 1.0),
            onChanged: (v) => onChanged(min + v * (max - min)),
          ),
        ],
      ),
    );
  }
}

/// Weight choice as the kit's compact segmented tabs.
class _WeightTile extends StatelessWidget {
  const _WeightTile({required this.value, required this.onChanged});

  final FontWeight value;
  final ValueChanged<FontWeight> onChanged;

  static const _options = <(FontWeight, String)>[
    (FontWeight.w400, 'Regular'),
    (FontWeight.w500, 'Medium'),
    (FontWeight.w600, 'Semi'),
    (FontWeight.w700, 'Bold'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = _options.indexWhere((o) => o.$1 == value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Weight',
              style: TextStyle(fontSize: 16, color: context.sp.title),
            ),
          ),
          STabs(
            labels: [for (final o in _options) o.$2],
            selected: index < 0 ? 2 : index,
            tabWidth: 62,
            onChanged: (i) => onChanged(_options[i].$1),
          ),
        ],
      ),
    );
  }
}

/// Label + circular swatches; the current colour gets an accent ring.
class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onColor;

  static const swatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFFFFEB3B),
    Color(0xFFFFC107),
    Color(0xFFFF5722),
    Color(0xFFE91E63),
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0x00000000),
    Color(0xB3000000),
    Color(0x80000000),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: p.title)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in swatches)
                _Swatch(
                  color: c,
                  selected: c.toARGB32() == color.toARGB32(),
                  onTap: () => onColor(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    // Translucent colours are shown blended over the card so the swatch is
    // still visible (and the outline drawing stays readable).
    final shown = Color.alphaBlend(color, p.card);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: shown,
          border: Border.all(
            color: selected ? p.accent : p.border,
            width: selected ? 2 : SHair.md,
          ),
        ),
      ),
    );
  }
}
