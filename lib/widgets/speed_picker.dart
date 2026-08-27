import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../core/theme/app_theme.dart';

/// A dialog that lets the user pick a playback speed.
/// The current speed is highlighted; selecting a speed calls [onSelected].
void showSpeedPicker(
  BuildContext context, {
  required double currentSpeed,
  required ValueChanged<double> onSelected,
}) {
  unawaited(
    showDialog<void>(
      context: context,
      builder: (ctx) => _SpeedPicker(
        currentSpeed: currentSpeed,
        onSelected: (speed) {
          Navigator.pop(ctx);
          onSelected(speed);
        },
      ),
    ),
  );
}

class _SpeedPicker extends StatelessWidget {
  const _SpeedPicker({required this.currentSpeed, required this.onSelected});

  final double currentSpeed;
  final ValueChanged<double> onSelected;

  static const speeds = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 480),
      title: Row(
        children: [
          Icon(
            FluentIcons.speed_high,
            size: 20,
            color: theme.accentColor.normal,
          ),
          const SizedBox(width: 10),
          const Text('Playback speed'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final speed in speeds)
              _SpeedTile(
                speed: speed,
                isSelected: speed == currentSpeed,
                onSelected: () => onSelected(speed),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.speed,
    required this.isSelected,
    required this.onSelected,
  });

  final double speed;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.normal;
    final label = speed == 1.0 ? 'Normal' : '${speed}x';

    return HoverButton(
      onPressed: onSelected,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: AppAlpha.tint)
                : hovered
                ? theme.resources.controlFillColorSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                speed == 1.0
                    ? FluentIcons.play
                    : speed > 1.0
                    ? FluentIcons.fast_forward
                    : FluentIcons.rewind,
                size: 14,
                color: isSelected ? accent : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: theme.typography.body?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? accent : null,
                  ),
                ),
              ),
              if (isSelected)
                Icon(FluentIcons.check_mark, color: accent, size: 14),
            ],
          ),
        );
      },
    );
  }
}
