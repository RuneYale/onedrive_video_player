import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as controls;

import '../core/theme/app_theme.dart';

/// A [VideoControlsBuilder] that renders Fluent-styled player controls with
/// subtitle, speed, audio, and lock buttons in the bottom bar.
///
/// Replaces media_kit's Material controls so the player matches the rest of
/// the app's WinUI look. Hover (or tap) reveals the controls; they auto-hide
/// after a few seconds of inactivity.
VideoControlsBuilder subtitleVideoControlsBuilder({
  required VoidCallback onSubtitleTap,
  required VoidCallback onSpeedTap,
  VoidCallback? onAudioTap,
  VoidCallback? onLockTap,
  bool locked = false,
}) {
  return (state) => _FluentVideoControls(
    state: state,
    onSubtitleTap: onSubtitleTap,
    onSpeedTap: onSpeedTap,
    onAudioTap: onAudioTap,
    onLockTap: onLockTap,
    locked: locked,
  );
}

class _FluentVideoControls extends StatefulWidget {
  const _FluentVideoControls({
    required this.state,
    required this.onSubtitleTap,
    required this.onSpeedTap,
    this.onAudioTap,
    this.onLockTap,
    this.locked = false,
  });

  final VideoState state;
  final VoidCallback onSubtitleTap;
  final VoidCallback onSpeedTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onLockTap;
  final bool locked;

  @override
  State<_FluentVideoControls> createState() => _FluentVideoControlsState();
}

class _FluentVideoControlsState extends State<_FluentVideoControls> {
  static const _hideDelay = Duration(seconds: 3);

  bool _visible = true;
  bool _volumeOpen = false;
  Timer? _hideTimer;

  Player get _player => widget.state.widget.controller.player;

  @override
  void initState() {
    super.initState();
    _restartHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _showAndSchedule() {
    if (!_visible) setState(() => _visible = true);
    // While the volume popup is open the bar must stay put.
    if (_volumeOpen) {
      _hideTimer?.cancel();
    } else {
      _restartHideTimer();
    }
  }

  void _toggle() {
    setState(() {
      _visible = !_visible;
      // Hiding the bar also dismisses the volume popup so it doesn't float
      // over the video on the next hover reveal.
      if (!_visible) _volumeOpen = false;
    });
    if (_visible) _restartHideTimer();
  }

  void _setVolumeOpen(bool open) {
    setState(() => _volumeOpen = open);
    if (open) {
      _hideTimer?.cancel();
    } else {
      _restartHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _showAndSchedule(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Buffering indicator (always visible while buffering)
            Center(
              child: StreamBuilder<bool>(
                stream: _player.stream.buffering,
                initialData: _player.state.buffering,
                builder: (context, snapshot) {
                  final buffering = snapshot.data ?? false;
                  if (!buffering) return const SizedBox.shrink();
                  return const SizedBox(
                    width: 56,
                    height: 56,
                    child: ProgressRing(strokeWidth: 4),
                  );
                },
              ),
            ),
            // Bottom control bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: _BottomBar(
                    player: _player,
                    locked: widget.locked,
                    volumeOpen: _volumeOpen,
                    onVolumeOpenChanged: _setVolumeOpen,
                    onSubtitleTap: widget.onSubtitleTap,
                    onSpeedTap: widget.onSpeedTap,
                    onAudioTap: widget.onAudioTap,
                    onLockTap: widget.onLockTap,
                    onInteract: _restartHideTimer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.player,
    required this.locked,
    required this.volumeOpen,
    required this.onVolumeOpenChanged,
    required this.onSubtitleTap,
    required this.onSpeedTap,
    this.onAudioTap,
    this.onLockTap,
    required this.onInteract,
  });

  final Player player;
  final bool locked;
  final bool volumeOpen;
  final ValueChanged<bool> onVolumeOpenChanged;
  final VoidCallback onSubtitleTap;
  final VoidCallback onSpeedTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onLockTap;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar
          _SeekBar(player: player, onInteract: onInteract),
          const SizedBox(height: 4),
          // Button row (Flex no longer clips children by default, so the
          // volume popup can float above it).
          Row(
            children: [
              _PlayPauseButton(player: player, onInteract: onInteract),
              _VolumeControl(
                player: player,
                onInteract: onInteract,
                open: volumeOpen,
                onOpenChanged: onVolumeOpenChanged,
              ),
              _PositionIndicator(player: player),
              const Spacer(),
              if (onLockTap != null)
                _ControlButton(
                  icon: locked ? FluentIcons.lock : FluentIcons.unlock,
                  tooltip: locked ? 'Unlock controls' : 'Lock controls',
                  onPressed: () {
                    onInteract();
                    onVolumeOpenChanged(false);
                    onLockTap!();
                  },
                ),
              if (onAudioTap != null)
                _ControlButton(
                  icon: FluentIcons.headset,
                  tooltip: 'Audio track',
                  onPressed: () {
                    onInteract();
                    onVolumeOpenChanged(false);
                    onAudioTap!();
                  },
                ),
              _ControlButton(
                icon: FluentIcons.closed_caption,
                tooltip: 'Subtitles',
                onPressed: () {
                  onInteract();
                  onVolumeOpenChanged(false);
                  onSubtitleTap();
                },
              ),
              _ControlButton(
                icon: FluentIcons.speed_high,
                tooltip: 'Playback speed',
                onPressed: () {
                  onInteract();
                  onVolumeOpenChanged(false);
                  onSpeedTap();
                },
              ),
              _ControlButton(
                icon: FluentIcons.full_screen,
                tooltip: 'Fullscreen',
                onPressed: () {
                  onInteract();
                  onVolumeOpenChanged(false);
                  unawaited(controls.toggleFullscreen(context));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.player, required this.onInteract});
  final Player player;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return _ControlButton(
          icon: playing ? FluentIcons.pause : FluentIcons.play,
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: () {
            onInteract();
            unawaited(player.playOrPause());
          },
        );
      },
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.player,
    required this.onInteract,
    required this.open,
    required this.onOpenChanged,
  });

  final Player player;
  final VoidCallback onInteract;

  /// Whether the volume popup is currently open.
  final bool open;

  /// Called when the popup opens (`true`) or closes (`false`).
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 100.0).clamp(0.0, 100.0);
        final muted = volume <= 0;
        final icon = muted
            ? FluentIcons.volume_disabled
            : volume < 50
            ? FluentIcons.volume1
            : FluentIcons.volume3;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _ControlButton(
              icon: icon,
              tooltip: 'Volume',
              onPressed: () {
                onInteract();
                onOpenChanged(!open);
              },
            ),
            // Popup floats above the button; the stack is as wide as the
            // button, so it overflows symmetrically on both sides.
            if (open)
              Positioned(
                bottom: 42,
                left: 0,
                right: 0,
                child: Center(
                  child: _VolumePopup(
                    player: player,
                    volume: volume,
                    muted: muted,
                    onVolumeChanged: (v) => unawaited(player.setVolume(v)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Vertical volume slider with percentage, mute toggle and mouse-wheel
/// support. Floats above the volume button in the player's bottom bar.
class _VolumePopup extends StatefulWidget {
  const _VolumePopup({
    required this.player,
    required this.volume,
    required this.muted,
    required this.onVolumeChanged,
  });

  final Player player;
  final double volume;
  final bool muted;
  final ValueChanged<double> onVolumeChanged;

  @override
  State<_VolumePopup> createState() => _VolumePopupState();
}

class _VolumePopupState extends State<_VolumePopup> {
  /// Last non-zero volume so unmute restores the previous level.
  double _lastNonZero = 100;

  void _adjust(double delta) {
    final next = (widget.volume + delta).clamp(0.0, 100.0);
    widget.onVolumeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final volume = widget.volume;
    if (volume > 0) _lastNonZero = volume;

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // A typical mouse-wheel notch is ±120 → ±10% per notch.
          _adjust(-event.scrollDelta.dy / 12);
        }
      },
      child: Container(
        width: 72,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppShadow.modal,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              '${volume.round()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: Slider(
                vertical: true,
                value: volume,
                min: 0,
                max: 100,
                onChanged: widget.onVolumeChanged,
              ),
            ),
            const SizedBox(height: 4),
            _ControlButton(
              icon: widget.muted
                  ? FluentIcons.volume_disabled
                  : FluentIcons.volume3,
              tooltip: widget.muted ? 'Unmute' : 'Mute',
              onPressed: () =>
                  widget.onVolumeChanged(widget.muted ? _lastNonZero : 0),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.onInteract});
  final Player player;
  final VoidCallback onInteract;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// Non-null while the user is dragging: freezes the slider thumb so the
  /// position stream doesn't fight the gesture.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        final maxMs = duration.inMilliseconds.toDouble();
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final valueMs =
                _dragValue ??
                position.inMilliseconds.toDouble().clamp(0.0, maxMs);
            return Slider(
              value: maxMs > 0 ? valueMs.clamp(0.0, maxMs) : 0.0,
              min: 0,
              max: maxMs > 0 ? maxMs : 1,
              onChangeStart: (_) => widget.onInteract(),
              onChanged: maxMs > 0
                  ? (v) => setState(() => _dragValue = v)
                  : null,
              onChangeEnd: maxMs > 0
                  ? (v) {
                      setState(() => _dragValue = null);
                      widget.onInteract();
                      unawaited(player.seek(Duration(milliseconds: v.round())));
                    }
                  : null,
            );
          },
        );
      },
    );
  }
}

class _PositionIndicator extends StatelessWidget {
  const _PositionIndicator({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, positionSnap) {
        final position = positionSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, durationSnap) {
            final duration = durationSnap.data ?? Duration.zero;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_fmt(position)} / ${_fmt(duration)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: HoverButton(
        onPressed: onPressed,
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          final pressed = states.contains(WidgetState.pressed);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: pressed
                  ? Colors.white.withValues(alpha: 0.18)
                  : hovered
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          );
        },
      ),
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}
