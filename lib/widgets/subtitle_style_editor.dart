import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/subtitle_style.dart';
import '../core/theme/app_theme.dart';
import '../providers/subtitle_style_provider.dart';

/// Lets the user customize the on-screen subtitle appearance. Changes are
/// applied live (via the watched [subtitleStyleProvider]) and persisted on
/// every adjustment. Designed to be presented as the content of a
/// [ContentDialog]; the host supplies the title and actions.
class SubtitleStyleEditor extends ConsumerWidget {
  const SubtitleStyleEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(subtitleStyleProvider);
    final notifier = ref.read(subtitleStyleProvider.notifier);

    return SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          _Preview(style: style),
          const SizedBox(height: 20),
          const _SectionLabel('Text'),
          _SliderRow(
            label: 'Size',
            valueText: style.fontSize.toStringAsFixed(0),
            value: style.fontSize,
            min: 12,
            max: 64,
            onChanged: (v) => notifier.update(style.copyWith(fontSize: v)),
          ),
          _SliderRow(
            label: 'Line height',
            valueText: style.lineHeight.toStringAsFixed(2),
            value: style.lineHeight,
            min: 1.0,
            max: 2.5,
            onChanged: (v) => notifier.update(style.copyWith(lineHeight: v)),
          ),
          _WeightPicker(
            value: style.fontWeight,
            onChanged: (w) => notifier.update(style.copyWith(fontWeight: w)),
          ),
          const SizedBox(height: 12),
          _ColorRow(
            label: 'Text color',
            color: style.color,
            onColor: (c) => notifier.update(style.copyWith(color: c)),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Background'),
          _SwitchRow(
            label: 'Show background',
            value: style.showBackground,
            onChanged: (v) =>
                notifier.update(style.copyWith(showBackground: v)),
          ),
          if (style.showBackground) ...[
            const SizedBox(height: 8),
            _ColorRow(
              label: 'Background color',
              color: style.backgroundColor,
              onColor: (c) =>
                  notifier.update(style.copyWith(backgroundColor: c)),
            ),
          ],
          const SizedBox(height: 16),
          const _SectionLabel('Outline'),
          _SwitchRow(
            label: 'Enable outline',
            value: style.outlineEnabled,
            onChanged: (v) =>
                notifier.update(style.copyWith(outlineEnabled: v)),
          ),
          if (style.outlineEnabled) ...[
            const SizedBox(height: 8),
            _SliderRow(
              label: 'Outline width',
              valueText: style.outlineWidth.toStringAsFixed(1),
              value: style.outlineWidth,
              min: 0.5,
              max: 6,
              onChanged: (v) =>
                  notifier.update(style.copyWith(outlineWidth: v)),
            ),
            const SizedBox(height: 4),
            _ColorRow(
              label: 'Outline color',
              color: style.outlineColor,
              onColor: (c) =>
                  notifier.update(style.copyWith(outlineColor: c)),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Builds the dialog actions for the subtitle style editor so the host page
/// stays declarative. [onClose] closes the host dialog.
List<Widget> subtitleStyleEditorActions(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onClose,
}) {
  return [
    HyperlinkButton(
      onPressed: () => ref.read(subtitleStyleProvider.notifier).reset(),
      child: const Text('Reset'),
    ),
    Button(onPressed: onClose, child: const Text('Close')),
  ];
}

class _Preview extends StatelessWidget {
  const _Preview({required this.style});
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C22),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Center(
            child: Icon(FluentIcons.video,
                size: 64, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StyledText(
                text: 'This is how your subtitles will look.',
                style: style,
                align: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StyledText extends StatelessWidget {
  const _StyledText({required this.text, required this.style, this.align});
  final String text;
  final SubtitleStyle style;
  final TextAlign? align;

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
    final textWidget = Text(text, textAlign: align, style: base);
    if (!style.outlineEnabled) return textWidget;
    final shadows = <Shadow>[
      for (final o in const [
        Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1),
        Offset(1, 1), Offset(-1, -1), Offset(1, -1), Offset(-1, 1),
      ])
        Shadow(
          color: style.outlineColor,
          offset: o * style.outlineWidth,
          blurRadius: 0,
        ),
    ];
    return Text(text, textAlign: align, style: base.copyWith(shadows: shadows));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: FluentTheme.of(context).typography.caption?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              )),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
          SizedBox(
            width: 44,
            child: Text(valueText,
                textAlign: TextAlign.end,
                style: TextStyle(color: context.colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ToggleSwitch(
        checked: value,
        onChanged: onChanged,
        content: Text(label),
      ),
    );
  }
}

class _WeightPicker extends StatelessWidget {
  const _WeightPicker({required this.value, required this.onChanged});
  final FontWeight value;
  final ValueChanged<FontWeight> onChanged;

  static const options = <(FontWeight, String)>[
    (FontWeight.w400, 'Regular'),
    (FontWeight.w500, 'Medium'),
    (FontWeight.w600, 'SemiBold'),
    (FontWeight.w700, 'Bold'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 110, child: Text('Weight')),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in options)
                  ToggleButton(
                    checked: value == o.$1,
                    onChanged: (_) => onChanged(o.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: Text(o.$2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.label, required this.color, required this.onColor});
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
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final c in swatches)
                  GestureDetector(
                    onTap: () => onColor(c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == c ? colors.accent : colors.outline,
                          width: color == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}