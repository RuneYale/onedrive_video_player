import 'package:flutter/material.dart';

import '../../core/theme/smartisan_kit.dart';
import 'subtitle_choices.dart';

/// Returned by [showChoiceDialog] for its footer action (subtitle
/// appearance), which is not a track id.
const choiceDialogAppearance = 'appearance';

IconData iconForChoice(ChoiceKind kind) => switch (kind) {
  ChoiceKind.off => SGlyphs.close,
  ChoiceKind.auto => SGlyphs.sparkle,
  ChoiceKind.embedded => SGlyphs.subtitles,
  ChoiceKind.external => SGlyphs.file,
  ChoiceKind.audio => SGlyphs.headphones,
};

/// Subtitle / audio picker: a flush list of 48dp rows inside the kit's dialog,
/// with the selected row in the accent colour. Returns the chosen id,
/// [choiceDialogAppearance] when the footer action is tapped, or null.
Future<String?> showChoiceDialog(
  BuildContext context, {
  required String title,
  required List<ChoiceGroup> groups,
  String? selectedId,
  String? appearanceLabel,
}) {
  final rows = <Widget>[];
  for (final group in groups) {
    if (group.choices.isEmpty) continue;
    if (rows.isNotEmpty) rows.add(const SDivider(indent: 16));
    rows.add(_GroupLabel(group.label));
    for (var i = 0; i < group.choices.length; i++) {
      final choice = group.choices[i];
      rows.add(
        _ChoiceRow(
          choice: choice,
          selected: choice.id == selectedId,
          onTap: () =>
              Navigator.of(context, rootNavigator: true).pop(choice.id),
        ),
      );
      if (i < group.choices.length - 1) {
        rows.add(const SDivider(indent: 16));
      }
    }
  }

  return Navigator.of(context, rootNavigator: true).push<String>(
    SDialogRoute<String>(
      barrierColor: context.sp.scrim,
      builder: (ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: SDialog(
            title: title,
            flushBody: true,
            body: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: rows,
              ),
            ),
            actions: [
              if (appearanceLabel != null)
                SDialogButton(
                  appearanceLabel,
                  onTap: () =>
                      Navigator.of(ctx).pop(choiceDialogAppearance),
                ),
              SDialogButton(
                'Cancel',
                primary: true,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Grey caption row above each group.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    color: context.sp.containerMisc,
    child: Text(
      label,
      style: TextStyle(fontSize: 12, color: context.sp.subtitle),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final Choice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return SPressable(
      onTap: onTap,
      builder: (context, pressed) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: pressed ? p.dialogActionPressed : Colors.transparent,
        child: Row(
          children: [
            Icon(
              iconForChoice(choice.kind),
              size: 18,
              color: selected ? p.accent : p.icon,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                choice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: pressed
                      ? p.titleOther
                      : (selected ? p.accent : p.title),
                ),
              ),
            ),
            if (selected) Icon(SGlyphs.check, size: 16, color: p.accent),
          ],
        ),
      ),
    );
  }
}
