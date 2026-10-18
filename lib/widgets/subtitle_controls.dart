import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as controls;

import '../core/theme/app_theme.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/utils/format.dart';
import '../core/widgets/smartisan_extras.dart';

/// A [VideoControlsBuilder] that draws the player bar in the app's Smartisan
/// language: a 4dp recessed seek track with a white thumb, icon buttons that
/// spring to 1.33x while held, and a white volume card. Replaces media_kit's
/// Material controls, which would otherwise be the one Material surface left
/// in the app.
VideoControlsBuilder subtitleVideoControlsBuilder({
  required VoidCallback onSubtitleTap,
  required VoidCallback onSpeedTap,
  VoidCallback? onAudioTap,
  VoidCallback? onLockTap,
  bool locked = false,
}) {
  return (state) => _PlayerControls(
    state: state,
    onSubtitleTap: onSubtitleTap,
    onSpeedTap: onSpeedTap,
    onAudioTap: onAudioTap,
    onLockTap: onLockTap,
    locked: locked,
  );
}

class _PlayerControls extends StatefulWidget {
  const _PlayerControls({
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
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {
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
    // While the volume card is open the bar must stay put.
    if (_volumeOpen) {
      _hideTimer?.cancel();
    } else {
      _restartHideTimer();
    }
  }

  void _toggle() {
    setState(() {
      _visible = !_visible;
      // Hiding the bar also dismisses the volume card so it doesn't float
      // over the video on the next reveal.
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
            // Buffering indicator stays visible for as long as it buffers.
            Center(
              child: StreamBuilder<bool>(
                stream: _player.stream.buffering,
                initialData: _player.state.buffering,
                builder: (context, snapshot) {
                  final buffering = snapshot.data ?? false;
                  if (!buffering) return const SizedBox.shrink();
                  return const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekBar(player: player, onInteract: onInteract),
              const SizedBox(height: 2),
              Row(
                children: [
                  _PlayPauseButton(player: player, onInteract: onInteract),
                  _VolumeControl(
                    player: player,
                    onInteract: onInteract,
                    open: volumeOpen,
                    onOpenChanged: onVolumeOpenChanged,
                  ),
                  _TimeLabel(player: player),
                  const Spacer(),
                  if (onLockTap != null)
                    _Control(
                      icon: SGlyphs.lock,
                      label: locked ? 'Unlock controls' : 'Lock controls',
                      onPressed: () {
                        onInteract();
                        onVolumeOpenChanged(false);
                        onLockTap!();
                      },
                    ),
                  if (onAudioTap != null)
                    _Control(
                      icon: SGlyphs.headphones,
                      label: 'Audio track',
                      onPressed: () {
                        onInteract();
                        onVolumeOpenChanged(false);
                        onAudioTap!();
                      },
                    ),
                  _Control(
                    icon: SGlyphs.subtitles,
                    label: 'Subtitles',
                    onPressed: () {
                      onInteract();
                      onVolumeOpenChanged(false);
                      onSubtitleTap();
                    },
                  ),
                  _Control(
                    icon: SGlyphs.speed,
                    label: 'Playback speed',
                    onPressed: () {
                      onInteract();
                      onVolumeOpenChanged(false);
                      onSpeedTap();
                    },
                  ),
                  _Control(
                    icon: SGlyphs.fullscreen,
                    label: 'Fullscreen',
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
          // Anchored above the bar (not to the button) so the card never runs
          // off the left edge of a narrow phone.
          if (volumeOpen)
            Positioned(
              left: 0,
              bottom: 58,
              child: _VolumeCard(player: player),
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
        return _Control(
          icon: playing ? SGlyphs.pause : SGlyphs.play,
          label: playing ? 'Pause' : 'Play',
          onPressed: () {
            onInteract();
            unawaited(player.playOrPause());
          },
        );
      },
    );
  }
}

/// White bar icon button with the kit's spring press.
class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SBarGlyphButton(
        icon: icon,
        size: 21,
        color: Colors.white,
        onTap: onPressed,
      ),
    ),
  );
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

  /// Whether the volume card is currently open.
  final bool open;

  /// Called when the card opens (`true`) or closes (`false`).
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 100.0).clamp(0.0, 100.0);
        return _Control(
          icon: volume <= 0 ? SGlyphs.mute : SGlyphs.volume,
          label: 'Volume',
          onPressed: () {
            onInteract();
            onOpenChanged(!open);
          },
        );
      },
    );
  }
}

/// White Smartisan card holding the volume slider, percentage and mute toggle.
class _VolumeCard extends StatefulWidget {
  const _VolumeCard({required this.player});

  final Player player;

  @override
  State<_VolumeCard> createState() => _VolumeCardState();
}

class _VolumeCardState extends State<_VolumeCard> {
  /// Last non-zero volume so unmute restores the previous level.
  double _lastNonZero = 100;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return StreamBuilder<double>(
      stream: widget.player.stream.volume,
      initialData: widget.player.state.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 100.0).clamp(0.0, 100.0);
        final muted = volume <= 0;
        if (!muted) _lastNonZero = volume;

        void setVolume(double v) =>
            unawaited(widget.player.setVolume(v.clamp(0.0, 100.0)));

        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              // A typical mouse-wheel notch is ±120 → ±10% per notch.
              setVolume(volume - event.scrollDelta.dy / 12);
            }
          },
          child: Container(
            width: 236,
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(SRadii.md),
              border: Border.all(color: p.border, width: SHair.xs),
              boxShadow: p.cardSmallShadow,
            ),
            child: Row(
              children: [
                SBarGlyphButton(
                  icon: muted ? SGlyphs.mute : SGlyphs.volume,
                  size: 18,
                  onTap: () => setVolume(muted ? _lastNonZero : 0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SSlider(
                    value: volume / 100,
                    onChanged: (v) => setVolume(v * 100),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${volume.round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.subtitle,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Seek track over the video: 4dp groove, accent fill, 16dp white thumb.
///
/// Drawn directly instead of using Material's [Slider] because the bar sits on
/// the video's black gradient, where the themed light/dark track and thumb
/// colours would fight the surface.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.onInteract});

  final Player player;
  final VoidCallback onInteract;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  static const double _height = 26;

  /// Non-null while dragging: freezes the thumb so the position stream doesn't
  /// fight the gesture.
  double? _dragFraction;

  void _updateFrom(double dx, double width, Duration duration) {
    if (width <= 0 || duration <= Duration.zero) return;
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragFraction = f);
  }

  void _commit(Duration duration) {
    final f = _dragFraction;
    if (f != null && duration > Duration.zero) {
      unawaited(
        widget.player.seek(
          Duration(milliseconds: (duration.inMilliseconds * f).round()),
        ),
      );
    }
    setState(() => _dragFraction = null);
    widget.onInteract();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final played = duration > Duration.zero
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  )
                : 0.0;
            final fraction = _dragFraction ?? played;
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    widget.onInteract();
                    _updateFrom(d.localPosition.dx, width, duration);
                    _commit(duration);
                  },
                  onHorizontalDragStart: (d) {
                    widget.onInteract();
                    _updateFrom(d.localPosition.dx, width, duration);
                  },
                  onHorizontalDragUpdate: (d) =>
                      _updateFrom(d.localPosition.dx, width, duration),
                  onHorizontalDragEnd: (_) => _commit(duration),
                  child: SizedBox(
                    height: _height,
                    child: CustomPaint(
                      painter: _SeekPainter(
                        fraction: fraction,
                        active: context.sp.accent,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({required this.fraction, required this.active});

  final double fraction;
  final Color active;

  static const double _trackHeight = 4;
  static const double _thumb = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final track = Rect.fromLTWH(
      0,
      centerY - _trackHeight / 2,
      size.width,
      _trackHeight,
    );
    final radius = const Radius.circular(_trackHeight / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = Colors.white.withValues(alpha: .24),
    );

    final filled = track.width * fraction;
    if (filled > 0) {
      final fill = Rect.fromLTWH(track.left, track.top, filled, track.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, radius),
        Paint()..color = active,
      );
    }

    final thumbCenter = Offset(
      (size.width - _thumb) * fraction + _thumb / 2,
      centerY,
    );
    canvas.drawCircle(
      thumbCenter,
      _thumb / 2,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.fraction != fraction || old.active != active;
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.player});

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
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${formatDuration(position)} / ${formatDuration(duration)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .9),
                  fontSize: 11,
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
