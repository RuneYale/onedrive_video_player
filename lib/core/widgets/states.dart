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

/// Error placeholder: the same pale glyph and grey copy as [EmptyState], plus
/// an optional technical [detail], a retry action and a second escape hatch
/// (e.g. "Choose another folder" when the library folder disappeared).
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;

  /// Technical cause (HTTP/mpv text). Shown small and secondary.
  final String? detail;
  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              SGlyphs.warningCircle,
              size: 72,
              color: const Color(0xFFD6D6D6),
            ),
            const SizedBox(height: 18),
            Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: p.disabled,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: p.subtitle),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: p.subtitleOther),
              ),
            ],
            if (onRetry != null || onSecondary != null) ...[
              const SizedBox(height: 22),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (onRetry != null)
                    IntrinsicWidth(
                      child: SButton(
                        'Try again',
                        kind: SButtonKind.small,
                        onPressed: onRetry,
                      ),
                    ),
                  if (secondaryLabel != null && onSecondary != null)
                    SButton(
                      secondaryLabel!,
                      kind: SButtonKind.text,
                      expand: false,
                      onPressed: onSecondary,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
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
