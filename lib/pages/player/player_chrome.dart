import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/smartisan_kit.dart';
import '../../core/widgets/smartisan_extras.dart';

/// Always-visible player top bar: close button and the video title over a soft
/// gradient so it stays readable on bright frames.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.onClose,
  });

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 16, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            SBarGlyphButton(
              icon: SGlyphs.close,
              semanticLabel: 'Close player',
              size: 20,
              color: Colors.white,
              onTap: onClose,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      blurRadius: 8,
                      color: Colors.black.withValues(alpha: 0.54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill showing a non-1.0 playback speed.
class PlayerSpeedBadge extends StatelessWidget {
  const PlayerSpeedBadge({super.key, required this.speed});

  final double speed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(SRadii.md),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: SHair.xs,
        ),
      ),
      child: Text(
        '${speed}x',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Transparent tap catcher shown while the controls are locked: tapping
/// reveals the unlock button for a few seconds.
class PlayerLockOverlay extends StatefulWidget {
  const PlayerLockOverlay({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  State<PlayerLockOverlay> createState() => _PlayerLockOverlayState();
}

class _PlayerLockOverlayState extends State<PlayerLockOverlay> {
  bool _showUnlock = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showUnlock = false);
    });
  }

  void _onTap() {
    setState(() => _showUnlock = true);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: ColoredBox(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity: _showUnlock ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  SGlyphs.lock,
                  size: 44,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 180,
                  child: SButton(
                    'Unlock',
                    kind: SButtonKind.sheet,
                    onPressed: widget.onUnlock,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
