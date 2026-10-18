import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../smartisan/smartisan_component_theme.dart';
import '../../smartisan/smartisan_palette.dart';
import '../../smartisan/smartisan_widgets.dart';

/// Smartisan confirmation dialog: grey 48dp title strip, white body, 54dp
/// action row (primary on the right). Destructive confirmations take the red
/// label the kit only defines for the bottom-menu danger button, so the
/// destruction still reads at a glance.
///
/// Returns `true` only when [confirmLabel] was tapped.
Future<bool> showSConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    SDialogRoute<bool>(
      barrierColor: context.sp.scrim,
      builder: (ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: SDialog(
            title: title,
            body: Text(message),
            actions: [
              SDialogButton(
                cancelLabel,
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              if (destructive)
                SDangerDialogButton(
                  confirmLabel,
                  onTap: () => Navigator.of(ctx).pop(true),
                )
              else
                SDialogButton(
                  confirmLabel,
                  primary: true,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// One button of a dialog action row with the kit's destructive red label.
class SDangerDialogButton extends StatelessWidget {
  const SDangerDialogButton(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SPressable(
    onTap: onTap,
    builder: (context, p) => Container(
      height: SDims.dialogAction,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p ? context.sp.dialogActionPressed : context.sp.dialogAction,
        border: Border(
          top: BorderSide(
            color: p
                ? context.sp.dialogActionBorderPressed
                : context.sp.dialogActionBorder,
            width: SHair.md,
          ),
        ),
      ),
      child: Text(
        label,
        style: SText.dialogAction.copyWith(color: context.sp.red),
      ),
    ),
  );
}

/// Shows a [SPopupMenu] anchored under [anchor] (the widget that opened it),
/// right-aligned to it and clamped inside the window. Tapping anywhere else
/// dismisses it.
Future<void> showSContextMenu(
  BuildContext anchor, {
  required List<SMenuItem> items,
  double width = 220,
}) async {
  final screen = MediaQuery.sizeOf(anchor);
  var origin = const Offset(24, 56);
  final box = anchor.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    final topLeft = box.localToGlobal(Offset.zero);
    origin = Offset(topLeft.dx + box.size.width - width, topLeft.dy + box.size.height + 6);
  }
  final menuHeight = items.length * 43 + 2;
  origin = Offset(
    origin.dx.clamp(8, math.max(8, screen.width - width - 8)),
    origin.dy.clamp(8, math.max(8, screen.height - menuHeight - 8)),
  );
  await Navigator.of(anchor, rootNavigator: true).push<void>(
    _SContextMenuRoute(origin: origin, width: width, items: items),
  );
}

/// Transparent-barrier popup route that hosts the menu card.
class _SContextMenuRoute extends PopupRoute<void> {
  _SContextMenuRoute({
    required this.origin,
    required this.width,
    required this.items,
  });

  final Offset origin;
  final double width;
  final List<SMenuItem> items;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'dismiss';

  @override
  Duration get transitionDuration => SMotion.fast;

  @override
  Duration get reverseTransitionDuration => SMotion.fast;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Stack(
    children: [
      Positioned(
        left: origin.dx,
        top: origin.dy,
        child: Material(
          type: MaterialType.transparency,
          child: SmartisanDialogEntrance(
            child: SPopupMenu(
              width: width,
              items: [
                for (final item in items)
                  SMenuItem(
                    item.label,
                    icon: item.icon,
                    onTap: () {
                      Navigator.of(context).pop();
                      item.onTap?.call();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}
