import 'package:flutter/material.dart';

import '../core/theme/smartisan_kit.dart';

/// Playback speeds offered by the picker.
const speedOptions = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// Bottom sheet with the kit's real wheel picker. The sheet slides up over
/// 300ms and down over 250ms, like the system's menu dialogs.
Future<void> showSpeedPicker(
  BuildContext context, {
  required double currentSpeed,
  required ValueChanged<double> onSelected,
}) async {
  final index = speedOptions.indexWhere(
    (s) => (s - currentSpeed).abs() < 0.001,
  );
  var selected = index < 0 ? speedOptions.indexOf(1.0) : index;

  final picked = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.sp.scrim,
    elevation: 0,
    sheetAnimationStyle: const AnimationStyle(
      duration: SMotion.base,
      reverseDuration: SMotion.sheetOut,
      curve: SMotion.decelerate,
      reverseCurve: SMotion.accelerate,
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SSheetHeader(
            title: 'Playback speed',
            onClose: () => Navigator.of(ctx).pop(),
            onConfirm: () => Navigator.of(ctx).pop(selected),
          ),
          Container(
            color: ctx.sp.sheetBody,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: SWheelPicker(
              columns: [
                [for (final s in speedOptions) _label(s)],
              ],
              selected: [selected],
              onChanged: (_, i) => setState(() => selected = i),
            ),
          ),
        ],
      ),
    ),
  );

  if (picked != null) onSelected(speedOptions[picked]);
}

String _label(double speed) => speed == 1.0 ? 'Normal' : '${speed}x';
