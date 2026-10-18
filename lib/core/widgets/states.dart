import 'package:flutter/material.dart';

import '../theme/smartisan_kit.dart';

/// Centred blank state, styled like the kit's [SEmptyState] (pale 96dp glyph,
/// bold grey title, lighter hint, optional action) but driven by the solid
/// glyph font instead of the kit's vector icon set.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 120,
              child: Center(
                child: Icon(icon, size: 96, color: const Color(0xFFD6D6D6)),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: p.disabled,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 5),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFFC8C8C8)),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              // IntrinsicWidth keeps the 30dp button a pill: inside a Column
              // an aligned Container would otherwise stretch to full width.
              IntrinsicWidth(
                child: SButton(
                  actionLabel!,
                  kind: SButtonKind.small,
                  onPressed: onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error placeholder: same layout, a warning glyph and a retry action.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: SGlyphs.warningCircle,
    title: 'Something went wrong',
    message: message,
    actionLabel: onRetry != null ? 'Try again' : null,
    onAction: onRetry,
  );
}

/// Calm loading placeholder: the accent arc and an optional grey label.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: context.sp.accent,
            backgroundColor: context.sp.divider,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 16),
          Text(
            label!,
            style: TextStyle(fontSize: 12, color: context.sp.subtitle),
          ),
        ],
      ],
    ),
  );
}
