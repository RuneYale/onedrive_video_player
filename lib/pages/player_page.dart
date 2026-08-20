import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/services/subtitle_preference_service.dart';
import '../core/services/subtitle_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import '../providers/drive_provider.dart';
import '../providers/subtitle_style_provider.dart';
import '../widgets/player_gesture_overlay.dart';
import '../widgets/speed_picker.dart';
import '../widgets/subtitle_controls.dart';
import '../widgets/subtitle_style_editor.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({required this.video, required this.siblings, super.key});

  final DriveItem video;
  final List<DriveItem> siblings;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const _progressInterval = Duration(seconds: 5);

  final PlaybackProgressService _progress = PlaybackProgressService();
  final SubtitlePreferenceService _subtitlePref = SubtitlePreferenceService();
  final SubtitleMatcher _matcher = const SubtitleMatcher();

  late final Player _player = Player(
    configuration: const PlayerConfiguration(title: 'OneDrive Video Player'),
  );
  late final VideoController _controller = VideoController(_player);

  BrightnessHelper? _brightnessHelper;
  VolumeHelper? _volumeHelper;

  PlaybackProgress? _savedProgress;
  List<DriveItem> _externalSubs = [];

  bool _loading = true;
  String? _error;
  String? _selectedSubtitleId;
  String? _loadingSubtitleId;
  bool _locked = false;
  bool _subtitlePanelOpen = false;
  bool _audioPanelOpen = false;
  double _speed = 1.0;

  Tracks _tracks = const Tracks();
  Track _currentTrack = const Track();

  Duration _lastSaved = Duration.zero;
  bool _wantsResume = false;
  bool _resumeSeekDone = false;
  bool _completed = false;
  bool _disposed = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Track>? _trackSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Brightness/volume helpers use platform channels that don't exist on
    // Windows (the underlying plugins are Android/iOS only), and the desktop
    // implementations aren't wired up in this codebase. The gesture overlay
    // null-checks the helpers, so leaving them null simply disables those
    // drag gestures on desktop.
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      _savedProgress = await _progress.get(widget.video.id);
      if (_savedProgress != null && _savedProgress!.isFinished) {
        await _progress.clear(widget.video.id);
        _savedProgress = null;
      }

      _externalSubs = _matcher.match(widget.video, widget.siblings);

      // When launched without siblings (e.g. from the Recent tab), fetch the
      // sibling files from the video's parent folder so external subtitle
      // matching still works. This is non-fatal: if the lookup fails we just
      // continue without external subtitles (embedded tracks remain
      // available). From the browser the sibling list is always provided, so
      // this extra round-trip only happens in the Recent relaunch path.
      if (widget.siblings.isEmpty && widget.video.parentId != null) {
        try {
          final children = await ref
              .read(graphServiceProvider)
              .listChildren(widget.video.parentId!);
          _externalSubs = _matcher.match(widget.video, children);
        } catch (_) {
          // Ignore — playback proceeds without external subtitles.
        }
      }
      if (!mounted) return;

      final url = await ref
          .read(graphServiceProvider)
          .getDownloadUrl(widget.video.id);
      if (!mounted) return;

      // Subscriptions are created once; retries (via [_retry]) reuse them.
      if (_positionSub == null) {
        _positionSub = _player.stream.position.listen(_onPosition);
        _durationSub = _player.stream.duration.listen(_onDuration);
        _completedSub = _player.stream.completed.listen(_onCompleted);
        _tracksSub = _player.stream.tracks.listen((t) {
          if (!mounted) return;
          setState(() => _tracks = t);
        });
        _tracks = _player.state.tracks;
        _trackSub = _player.stream.track.listen((t) {
          if (!mounted) return;
          setState(() => _currentTrack = t);
        });
        _currentTrack = _player.state.track;
        // Playback errors (e.g. the pre-authenticated download URL expiring
        // mid-playback, or a network drop) surface here so the user gets a
        // retry button instead of a frozen player.
        _errorSub = _player.stream.error.listen((error) {
          if (!mounted || error.isEmpty) return;
          setState(() {
            _error = error;
            _loading = false;
          });
        });
      }

      await _player.open(Media(url), play: false);
      if (!mounted) return;

      if (_savedProgress != null) {
        _wantsResume = true;
        // A (re)open starts from zero, so the resume seek must be re-issued
        // and re-confirmed even if a previous open already completed it.
        _resumeSeekDone = false;
        if (_player.state.duration > Duration.zero) {
          unawaited(_seekToSavedAndPlay());
        }
      } else {
        await _player.play();
      }

      if (mounted) setState(() => _loading = false);
      // Restore this video's last subtitle choice without blocking playback.
      // Stale ids (e.g. libmpv re-enumerating embedded track ids) are
      // ignored silently by [_applySavedSubtitle].
      if (mounted) unawaited(_applySavedSubtitle());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Retries opening the video after a playback error. The download URL is
  /// re-resolved because the previous one may have expired.
  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
    });
    unawaited(_open());
  }

  void _onPosition(Duration position) {
    // Periodic auto-save so a crash doesn't lose much progress.
    if ((position - _lastSaved).abs() > _progressInterval) {
      _lastSaved = position;
      if (position > const Duration(seconds: 3) && !_completed) {
        unawaited(_progress.save(
          widget.video.id,
          position,
          _player.state.duration,
          name: widget.video.name,
          thumbnailUrl: widget.video.thumbnailUrl,
          size: widget.video.size,
          parentId: widget.video.parentId,
        ));
      }
    }
  }

  void _onDuration(Duration duration) {
    if (_wantsResume && !_resumeSeekDone && duration > Duration.zero) {
      unawaited(_seekToSavedAndPlay());
    }
  }

  /// Seeks to the saved position once, waits for the stream to report the
  /// seek landed, then starts playback. Verifying via the position stream
  /// (instead of fire-and-forget + snackbar) means a failed seek doesn't get
  /// masked by a "Resumed" toast.
  Future<void> _seekToSavedAndPlay() async {
    if (_resumeSeekDone) return;
    _resumeSeekDone = true;

    final saved = _savedProgress;
    if (saved == null) {
      await _player.play();
      return;
    }
    final target = Duration(seconds: saved.positionSeconds.round());

    await _player.seek(target);

    // Wait for the position stream to confirm the seek landed.
    const tolerance = Duration(seconds: 2);
    const timeout = Duration(seconds: 5);
    try {
      await _player.stream.position.firstWhere(
        (p) => (p - target).abs() <= tolerance,
      ).timeout(timeout);
    } catch (_) {
      // Timeout or stream error — continue anyway.
    }

    if (_disposed || !mounted) return;
    await _player.play();
    _showResumeInfoBar(target);
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    _completed = true;
    unawaited(_progress.clear(widget.video.id));
  }

  void _showResumeInfoBar(Duration position) {
    if (!mounted) return;
    unawaited(displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: Text('Resumed from ${_formatDuration(position)}'),
        severity: InfoBarSeverity.info,
      );
    }, duration: const Duration(seconds: 3)));
  }

  // --- Subtitles ----------------------------------------------------------

  List<_SubtitleChoice> get _choices {
    final list = <_SubtitleChoice>[
      const _OffChoice(),
      const _AutoChoice(),
    ];
    for (final t in _tracks.subtitle) {
      if (t.id == 'auto' || t.id == 'no') continue;
      list.add(_EmbeddedChoice(track: t));
    }
    for (final s in _externalSubs) {
      list.add(_ExternalChoice(item: s));
    }
    return list;
  }

  Future<void> _applySubtitle(_SubtitleChoice choice,
      {bool silent = false}) async {
    setState(() => _loadingSubtitleId = choice.id);
    try {
      switch (choice) {
        case _OffChoice():
          await _player.setSubtitleTrack(SubtitleTrack.no());
        case _AutoChoice():
          await _player.setSubtitleTrack(SubtitleTrack.auto());
        case _EmbeddedChoice(:final track):
          await _player.setSubtitleTrack(track);
        case _ExternalChoice(:final item):
          final url =
              await ref.read(graphServiceProvider).getDownloadUrl(item.id);
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(url, title: item.name),
          );
      }
      if (!mounted) return;
      setState(() {
        _selectedSubtitleId = choice.id;
        _loadingSubtitleId = null;
      });
      // Remember the choice so re-opening this video restores it.
      unawaited(_subtitlePref.save(widget.video.id, choice.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSubtitleId = null);
      // Silent restoration failures (stale track id, expired subtitle URL)
      // shouldn't pester the user — fall back to the default silently.
      if (silent) return;
      unawaited(displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: Text('Could not load subtitle: $e'),
          severity: InfoBarSeverity.error,
        );
      }));
    }
  }

  /// Restores the subtitle choice last saved for this video, if the choice
  /// still exists for the current file. Embedded-track ids depend on the
  /// demuxer's track enumeration, so those wait (briefly) for tracks to
  /// report before matching; anything stale is ignored silently.
  Future<void> _applySavedSubtitle() async {
    final savedId = await _subtitlePref.get(widget.video.id);
    if (!mounted || _disposed || savedId == null) return;

    // The user already picked a subtitle this session (or the restore for a
    // previous open completed) — don't clobber their explicit choice.
    if (_selectedSubtitleId != null) return;

    // External subtitles come from the sibling list (already known); only
    // embedded choices require the demuxer's track report.
    if (savedId.startsWith('embedded:') && _tracks.subtitle.isEmpty) {
      try {
        await _player.stream.tracks
            .firstWhere((t) => t.subtitle.isNotEmpty)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // No embedded tracks reported in time — the match below will miss.
      }
      if (!mounted || _disposed || _selectedSubtitleId != null) return;
    }

    _SubtitleChoice? choice;
    for (final c in _choices) {
      if (c.id == savedId) {
        choice = c;
        break;
      }
    }
    if (choice != null) {
      await _applySubtitle(choice, silent: true);
    }
  }

  // --- Speed --------------------------------------------------------------

  void _onSpeedTap() {
    showSpeedPicker(
      context,
      currentSpeed: _speed,
      onSelected: (speed) {
        unawaited(_player.setRate(speed));
        setState(() => _speed = speed);
      },
    );
  }

  // --- Disposal -----------------------------------------------------------

  @override
  void dispose() {
    // Set first so any in-flight async loop (resume confirmation) stops
    // before the player underneath it is disposed.
    _disposed = true;
    final position = _player.state.position;
    final duration = _player.state.duration;
    final shouldSave = !_completed && position > const Duration(seconds: 3);

    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_tracksSub?.cancel());
    unawaited(_trackSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_player.dispose());

    if (shouldSave) {
      // Fire-and-forget: the widget is being torn down, so there is nothing
      // to await against. The service writes through SharedPreferences which
      // completes on its own.
      unawaited(_progress.save(
        widget.video.id,
        position,
        duration,
        name: widget.video.name,
        thumbnailUrl: widget.video.thumbnailUrl,
        size: widget.video.size,
        parentId: widget.video.parentId,
      ));
    }
    super.dispose();
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subtitleStyle = ref.watch(subtitleStyleProvider);

    Widget body;
    if (_error != null) {
      body = ErrorState(message: _error!, onRetry: _retry);
    } else if (_loading) {
      body = const LoadingState(label: 'Opening video…');
    } else {
      body = Stack(
        children: [
          Video(
            controller: _controller,
            fill: AppTheme.playerSurface,
            controls: _locked
                ? (_) => const SizedBox.shrink()
                : subtitleVideoControlsBuilder(
                    onSubtitleTap: () => _showSubtitlePicker(context),
                    onSpeedTap: _onSpeedTap,
                    onAudioTap: _audioTracks.length > 1
                        ? () => _showAudioPicker(context)
                        : null,
                    onLockTap: () {
                      setState(() => _locked = true);
                    },
                    locked: _locked,
                  ),
            subtitleViewConfiguration: SubtitleViewConfiguration(
              visible: true,
              style: TextStyle(
                fontSize: subtitleStyle.fontSize,
                fontWeight: subtitleStyle.fontWeight,
                color: subtitleStyle.color,
                height: subtitleStyle.lineHeight,
                background: subtitleStyle.showBackground
                    ? (Paint()..color = subtitleStyle.backgroundColor)
                    : null,
              ),
            ),
          ),
          // Gesture overlay — only claims drags, taps fall through to Video
          if (!_locked)
            Positioned.fill(
              child: PlayerGestureOverlay(
                player: _player,
                brightnessHelper: _brightnessHelper,
                volumeHelper: _volumeHelper,
              ),
            ),
          // Lock indicator + unlock button
          if (_locked)
            Positioned.fill(
              child: _LockScreen(
                onUnlock: () {
                  setState(() => _locked = false);
                },
              ),
            ),
          // Speed badge
          if (!_locked && _speed != 1.0)
            Positioned(
              bottom: 60,
              right: 16,
              child: _SpeedBadge(speed: _speed),
            ),
        ],
      );
    }

    final choices = _choices;
    _SubtitleChoice? selectedChoice;
    for (final c in choices) {
      if (c.id == _selectedSubtitleId) {
        selectedChoice = c;
        break;
      }
    }

    return PopScope(
      canPop: !_anyPanelOpen,
      onPopInvokedWithResult: (didPop, _) {
        // System back closes any open floating panel first instead of leaving
        // the player.
        if (!didPop) _closeAllPanels();
      },
      child: ColoredBox(
        color: AppTheme.playerSurface,
        child: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              if (_anyPanelOpen) {
                _closeAllPanels();
              } else {
                Navigator.of(context).pop();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              body,
              // Always-visible top bar: back button + title
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _TopBar(
                    title: widget.video.name,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              // Floating subtitle selection panel (overlay)
              if (_subtitlePanelOpen && !_locked)
                Positioned.fill(
                  child: Stack(
                    children: [
                      // Scrim — tap outside the panel to close it.
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          builder: (context, t, child) => Opacity(
                            opacity: 0.4 * t,
                            child: child,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeSubtitlePanel,
                            child: const ColoredBox(color: Colors.black),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 64,
                        right: 16,
                        child: _PanelEntrance(
                          child: _SubtitlePanel(
                          video: widget.video,
                          choices: choices,
                          selected: selectedChoice,
                          loadingId: _loadingSubtitleId,
                          onSelected: _applySubtitle,
                          onCustomize: () => _showAppearanceEditor(context),
                          onClose: _closeSubtitlePanel,
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              // Floating audio track selection panel (overlay)
              if (_audioPanelOpen && !_locked)
                Positioned.fill(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          builder: (context, t, child) => Opacity(
                            opacity: 0.4 * t,
                            child: child,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeAudioPanel,
                            child: const ColoredBox(color: Colors.black),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 64,
                        right: 16,
                        child: _PanelEntrance(
                          child: _AudioPanel(
                          tracks: _audioTracks,
                          selected: _currentTrack.audio,
                          onSelected: _applyAudioTrack,
                          onClose: _closeAudioPanel,
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  bool get _anyPanelOpen => _subtitlePanelOpen || _audioPanelOpen;

  /// Real audio tracks (excluding the libmpv 'auto'/'no' placeholders).
  List<AudioTrack> get _audioTracks =>
      _tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();

  void _showSubtitlePicker(BuildContext context) {
    setState(() {
      _audioPanelOpen = false;
      _subtitlePanelOpen = true;
    });
  }

  void _closeSubtitlePanel() {
    if (_subtitlePanelOpen) setState(() => _subtitlePanelOpen = false);
  }

  void _showAudioPicker(BuildContext context) {
    setState(() {
      _subtitlePanelOpen = false;
      _audioPanelOpen = true;
    });
  }

  void _closeAudioPanel() {
    if (_audioPanelOpen) setState(() => _audioPanelOpen = false);
  }

  void _closeAllPanels() {
    if (_anyPanelOpen) {
      setState(() {
        _subtitlePanelOpen = false;
        _audioPanelOpen = false;
      });
    }
  }

  Future<void> _applyAudioTrack(AudioTrack track) async {
    try {
      await _player.setAudioTrack(track);
      // _trackSub updates _currentTrack and rebuilds the panel, so the
      // checkmark moves automatically �� no manual setState needed.
    } catch (e) {
      if (!mounted) return;
      unawaited(displayInfoBar(context, builder: (context, close) {
        return InfoBar(
          title: Text('Could not switch audio track: $e'),
          severity: InfoBarSeverity.error,
        );
      }));
    }
  }

  /// Opens the subtitle appearance editor as a Fluent ContentDialog.
  void _showAppearanceEditor(BuildContext context) {
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        title: Row(
          children: [
            Icon(FluentIcons.font,
                size: 20, color: FluentTheme.of(ctx).accentColor.normal),
            const SizedBox(width: 10),
            const Expanded(child: Text('Subtitle appearance')),
            IconButton(
              icon: const Icon(FluentIcons.chrome_close, size: 12),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: const SubtitleStyleEditor(),
        actions: subtitleStyleEditorActions(context, ref,
            onClose: () => Navigator.of(ctx).pop()),
      ),
    ));
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(FluentIcons.chrome_close, size: 14),
            onPressed: onClose,
          ),
          const SizedBox(width: 4),
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
                      color: Colors.black.withValues(alpha: 0.54))
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Speed badge
// ---------------------------------------------------------------------------

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({required this.speed});
  final double speed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
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

// ---------------------------------------------------------------------------
// Panel entrance animation
// ---------------------------------------------------------------------------

/// Entrance animation for floating panels: fade in while rising slightly.
/// Runs once when the panel first appears.
class _PanelEntrance extends StatelessWidget {
  const _PanelEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Lock screen overlay
// ---------------------------------------------------------------------------

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
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
      onTap: _onTap,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity: _showUnlock ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.lock,
                    size: 48, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Button(
                  onPressed: widget.onUnlock,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.unlock, size: 14),
                      SizedBox(width: 8),
                      Text('Unlock'),
                    ],
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

// ---------------------------------------------------------------------------
// Subtitle panel
// ---------------------------------------------------------------------------

class _SubtitlePanel extends StatelessWidget {
  const _SubtitlePanel({
    required this.video,
    required this.choices,
    required this.selected,
    required this.loadingId,
    required this.onSelected,
    required this.onCustomize,
    required this.onClose,
  });

  final DriveItem video;
  final List<_SubtitleChoice> choices;
  final _SubtitleChoice? selected;
  final String? loadingId;
  final ValueChanged<_SubtitleChoice> onSelected;
  final VoidCallback onCustomize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Split the flat choice list into visually grouped sections.
    final general = <_SubtitleChoice>[];
    final embedded = <_SubtitleChoice>[];
    final external = <_SubtitleChoice>[];
    for (final c in choices) {
      if (c.id == 'off' || c.id == 'auto') {
        general.add(c);
      } else if (c.id.startsWith('embedded:')) {
        embedded.add(c);
      } else {
        external.add(c);
      }
    }

    Widget tile(_SubtitleChoice c) {
      final isSelected = c.id == selected?.id;
      return _ChoiceTile(
        choice: c,
        selected: isSelected,
        loading: c.id == loadingId,
        onTap: () => onSelected(c),
      );
    }

    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Icon(FluentIcons.closed_caption,
                    size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Subtitles',
                      style: FluentTheme.of(context).typography.bodyStrong),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.chrome_close, size: 12),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(),
          // Sections
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              children: [
                if (general.isNotEmpty) ...[
                  const _GroupLabel('State'),
                  for (final c in general) tile(c),
                  const SizedBox(height: 8),
                ],
                if (embedded.isNotEmpty) ...[
                  const _GroupLabel('Embedded tracks'),
                  for (final c in embedded) tile(c),
                  const SizedBox(height: 8),
                ],
                if (external.isNotEmpty) ...[
                  const _GroupLabel('External subtitles'),
                  for (final c in external) tile(c),
                ],
              ],
            ),
          ),
          const Divider(),
          // Footer — appearance customization
          HoverButton(
            onPressed: onCustomize,
            builder: (context, states) {
              final hovered = states.contains(WidgetState.hovered);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: hovered
                      ? colors.onSurface.withValues(alpha: 0.04)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(FluentIcons.font,
                        size: 14, color: colors.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Customize appearance',
                          style: TextStyle(
                              fontSize: 13, color: colors.onSurface)),
                    ),
                    Icon(FluentIcons.chevron_right,
                        size: 12, color: colors.onSurfaceVariant),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Small uppercase section label used to group subtitle choices.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final _SubtitleChoice choice;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.10)
                : hovered
                    ? colors.onSurface.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(choice.icon,
                  size: 14,
                  color:
                      selected ? colors.accent : colors.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  choice.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? colors.accent : colors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              else if (selected)
                Icon(FluentIcons.check_mark, size: 12, color: colors.accent),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Audio panel
// ---------------------------------------------------------------------------

class _AudioPanel extends StatelessWidget {
  const _AudioPanel({
    required this.tracks,
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  final List<AudioTrack> tracks;
  final AudioTrack selected;
  final ValueChanged<AudioTrack> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Icon(FluentIcons.headset, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Audio track',
                      style: FluentTheme.of(context).typography.bodyStrong),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.chrome_close, size: 12),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final t = tracks[index];
                final isSelected = t.id == selected.id;
                return HoverButton(
                  onPressed: () => onSelected(t),
                  builder: (context, states) {
                    final hovered = states.contains(WidgetState.hovered);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.accent.withValues(alpha: 0.10)
                            : hovered
                                ? colors.onSurface.withValues(alpha: 0.05)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(FluentIcons.music_note,
                              size: 14,
                              color: isSelected
                                  ? colors.accent
                                  : colors.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.title ?? t.language ?? 'Track ${t.id}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colors.accent
                                    : colors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected)
                            Icon(FluentIcons.check_mark,
                                size: 12, color: colors.accent),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtitle choices
// ---------------------------------------------------------------------------

sealed class _SubtitleChoice {
  const _SubtitleChoice();
  String get id;
  String get label;
  IconData get icon;
}

class _OffChoice extends _SubtitleChoice {
  const _OffChoice();
  @override
  String get id => 'off';
  @override
  String get label => 'Off';
  @override
  IconData get icon => FluentIcons.clear;
}

class _AutoChoice extends _SubtitleChoice {
  const _AutoChoice();
  @override
  String get id => 'auto';
  @override
  String get label => 'Auto';
  @override
  IconData get icon => FluentIcons.auto_enhance_on;
}

class _EmbeddedChoice extends _SubtitleChoice {
  const _EmbeddedChoice({required this.track});
  final SubtitleTrack track;
  @override
  String get id => 'embedded:${track.id}';
  @override
  String get label => track.title ?? track.language ?? 'Track ${track.id}';
  @override
  IconData get icon => FluentIcons.closed_caption;
}

class _ExternalChoice extends _SubtitleChoice {
  const _ExternalChoice({required this.item});
  final DriveItem item;
  @override
  String get id => 'external:${item.id}';
  @override
  String get label => item.name;
  @override
  IconData get icon => FluentIcons.document;
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}