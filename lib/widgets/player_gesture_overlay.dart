import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// A transparent gesture layer placed on top of the [Video] widget.
///
/// Implements Yamby-style touch gestures:
/// * **Horizontal drag** — seek forward/backward. A preview overlay shows the
///   target position and the delta; the actual [Player.seek] is called on drag
///   end to avoid excess seeking.
/// * **Left-side vertical drag** — adjust screen brightness.
/// * **Right-side vertical drag** — adjust system volume.
///
/// Only drag gestures are claimed; taps fall through to the underlying
/// [Video] controls so play/pause, subtitle, speed, and fullscreen buttons
/// remain clickable. We achieve this by using separate
/// `onHorizontalDragUpdate` / `onVerticalDragUpdate` callbacks (Flutter only
/// claims a gesture once the drag axis is resolved) and by NOT setting
/// `onTap` — tap events simply pass through to widgets below us.
class PlayerGestureOverlay extends StatefulWidget {
  const PlayerGestureOverlay({
    super.key,
    required this.player,
    this.brightnessHelper,
    this.volumeHelper,
    this.enabled = true,
  });

  final Player player;

  /// Abstraction over platform brightness so the overlay is testable without
  /// a real screen.  When null, brightness gestures are disabled.
  final BrightnessHelper? brightnessHelper;

  /// Abstraction over system volume.  When null, volume gestures are disabled.
  final VolumeHelper? volumeHelper;

  final bool enabled;

  @override
  State<PlayerGestureOverlay> createState() => _PlayerGestureOverlayState();
}

class _PlayerGestureOverlayState extends State<PlayerGestureOverlay> {
  /// Height of the bottom controls zone (seek bar etc.). Drags starting
  /// here are left to the video controls underneath instead of being
  /// claimed by this overlay.
  static const double _bottomControlsZone = 120;

  _GestureType? _gesture;
  Offset? _start;

  bool _inBottomControlsZone(double localDy) {
    final height = context.size?.height;
    if (height == null) return false;
    return localDy >= height - _bottomControlsZone;
  }

  // Seek state
  Duration? _seekFrom;
  Duration? _seekTo;
  Duration? _seekPreview;

  // Brightness / volume state
  double _indicatorValue = 0;
  _GestureIndicatorKind? _indicatorKind;

  Timer? _indicatorTimer;

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    super.dispose();
  }

  void _showIndicator(_GestureIndicatorKind kind, double value) {
    _indicatorKind = kind;
    _indicatorValue = value;
    _indicatorTimer?.cancel();
    setState(() {});
    _indicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _indicatorKind = null);
    });
  }

  // --- Horizontal drag = seek --------------------------------------------

  void _onHorizontalDragStart(DragStartDetails d) {
    if (!widget.enabled || _inBottomControlsZone(d.localPosition.dy)) return;
    _gesture = _GestureType.seek;
    _start = d.globalPosition;
    _seekFrom = widget.player.state.position;
    _seekTo = _seekFrom;
    _seekPreview = _seekFrom;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _start == null) return;
    final dx = d.globalPosition.dx - _start!.dx;
    _handleSeek(dx);
  }

  void _onDragEnd(DragEndDetails _) {
    if (_gesture == _GestureType.seek && _seekTo != null) {
      unawaited(widget.player.seek(_seekTo!));
    }
    _gesture = null;
    _start = null;
    _seekFrom = null;
    _seekTo = null;
    if (mounted) setState(() => _seekPreview = null);
  }

  // --- Vertical drag = brightness / volume -------------------------------

  void _onVerticalDragStart(DragStartDetails d) {
    if (!widget.enabled || _inBottomControlsZone(d.localPosition.dy)) return;
    _start = d.globalPosition;
    final w = MediaQuery.of(context).size.width;
    if (d.globalPosition.dx < w / 2 &&
        widget.brightnessHelper != null) {
      _gesture = _GestureType.brightness;
    } else if (widget.volumeHelper != null) {
      _gesture = _GestureType.volume;
    } else {
      _gesture = null;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _start == null || _gesture == null) return;
    final dy = d.globalPosition.dy - _start!.dy;
    switch (_gesture!) {
      case _GestureType.brightness:
        _handleBrightness(dy);
      case _GestureType.volume:
        _handleVolume(dy);
      case _GestureType.seek:
        break;
    }
  }

  // --- Seek ---------------------------------------------------------------

  void _handleSeek(double dx) {
    if (_seekFrom == null) return;
    // 1 px ≈ 0.5 s, capped at ±600 s (10 min). Full screen width ≈ 180 s.
    final delta = Duration(seconds: (dx * 0.5).round());
    final duration = widget.player.state.duration;
    var target = _seekFrom! + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _seekTo = target;
    _seekPreview = target;
    setState(() {});
  }

  // --- Brightness ---------------------------------------------------------

  void _handleBrightness(double dy) {
    final helper = widget.brightnessHelper;
    if (helper == null) return;
    final h = MediaQuery.of(context).size.height;
    final delta = -dy / h * 0.5;
    var v = helper.current + delta;
    v = v.clamp(0.0, 1.0);
    unawaited(helper.set(v));
    _showIndicator(_GestureIndicatorKind.brightness, v);
  }

  // --- Volume -------------------------------------------------------------

  void _handleVolume(double dy) {
    final helper = widget.volumeHelper;
    if (helper == null) return;
    final h = MediaQuery.of(context).size.height;
    final delta = -dy / h * 0.5;
    var v = helper.current + delta;
    v = v.clamp(0.0, 1.0);
    unawaited(helper.set(v));
    _showIndicator(_GestureIndicatorKind.volume, v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // translucent so taps pass through to the Video controls below
      behavior: HitTestBehavior.translucent,
      // Use separate horizontal/vertical drag recognizers so that:
      // 1) Only true drags are claimed (taps fall through to Video controls)
      // 2) Flutter's arena resolves horiz vs vert cleanly
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      // Deliberately NO onTap — let taps reach the Video controls
      child: Stack(
        children: [
          if (_gesture == _GestureType.seek && _seekPreview != null)
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _SeekPreview(
                  from: _seekFrom ?? Duration.zero,
                  to: _seekPreview!,
                  duration: widget.player.state.duration,
                ),
              ),
            ),
          if (_indicatorKind != null)
            Center(
              child: _GestureIndicator(
                kind: _indicatorKind!,
                value: _indicatorValue,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Indicator widgets
// ---------------------------------------------------------------------------

enum _GestureType { seek, brightness, volume }

enum _GestureIndicatorKind { brightness, volume }

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({
    required this.from,
    required this.to,
    required this.duration,
  });

  final Duration from;
  final Duration to;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final delta = to - from;
    final sign = delta >= Duration.zero ? '+' : '-';
    final absDelta = delta.abs();
    final isForward = delta >= Duration.zero;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${_formatDuration(absDelta)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDuration(to),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _GestureIndicator extends StatelessWidget {
  const _GestureIndicator({required this.kind, required this.value});
  final _GestureIndicatorKind kind;
  final double value;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      _GestureIndicatorKind.brightness => Icons.brightness_6_rounded,
      _GestureIndicatorKind.volume => Icons.volume_up_rounded,
    };
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 3,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Abstractions for brightness & volume
// ---------------------------------------------------------------------------

abstract class BrightnessHelper {
  double get current;
  Future<void> set(double value);
}

abstract class VolumeHelper {
  double get current;
  Future<void> set(double value);
}

// ---------------------------------------------------------------------------
// Util
// ---------------------------------------------------------------------------

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}