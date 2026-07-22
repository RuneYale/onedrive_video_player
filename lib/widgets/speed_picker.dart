import 'package:flutter/material.dart';

/// A bottom sheet that lets the user pick a playback speed.
/// The current speed is highlighted; selecting a speed calls [onSelected].
void showSpeedPicker(
  BuildContext context, {
  required double currentSpeed,
  required ValueChanged<double> onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _SpeedPicker(
      currentSpeed: currentSpeed,
      onSelected: (speed) {
        Navigator.pop(ctx);
        onSelected(speed);
      },
    ),
  );
}

class _SpeedPicker extends StatelessWidget {
  const _SpeedPicker({
    required this.currentSpeed,
    required this.onSelected,
  });

  final double currentSpeed;
  final ValueChanged<double> onSelected;

  static const speeds = <double>[
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, size: 22, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('Playback speed',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
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
    final scheme = Theme.of(context).colorScheme;
    final label = speed == 1.0 ? 'Normal' : '${speed}x';

    return InkWell(
      onTap: onSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(
              speed == 1.0
                  ? Icons.play_arrow_rounded
                  : speed > 1.0
                      ? Icons.fast_forward_rounded
                      : Icons.fast_rewind_rounded,
              size: 18,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? scheme.primary : null,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, color: scheme.primary, size: 22),
          ],
        ),
      ),
    );
  }
}