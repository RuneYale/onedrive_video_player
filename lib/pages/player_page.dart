import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as mk;

import '../core/errors/app_failure.dart';
import '../core/models/drive_item.dart';
import '../core/models/subtitle_style.dart';
import '../core/services/playback_progress_service.dart';
import '../core/services/subtitle_preference_service.dart';
import '../core/services/subtitle_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/utils/format.dart';
import '../core/widgets/states.dart';
import '../providers/drive_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/subtitle_style_provider.dart';
import '../widgets/player_gesture_overlay.dart';
import '../widgets/speed_picker.dart';
import '../widgets/subtitle_controls.dart';
import '../widgets/subtitle_style_editor.dart';
import 'player/choice_dialog.dart';
import 'player/player_chrome.dart';
import 'player/subtitle_choices.dart';

/// Sent by the subtitle dialog's appearance action.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({required this.video, required this.siblings, super.key});

  final DriveItem video;
  final List<DriveItem> siblings;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const _progressInterval = Duration(seconds: 30);

  late final PlaybackProgressService _progress = ref.read(
    playbackProgressServiceProvider,
  );
  late final SubtitlePreferenceService _subtitlePref = ref.read(
    subtitlePreferenceServiceProvider,
  );
  final SubtitleMatcher _matcher = const SubtitleMatcher();

  late final Player _player = Player(
    configuration: PlayerConfiguration(
      title: 'OneDrive Video Player',
      // libass renders ASS/SSA subtitles (fonts, colors, karaoke, inline
      // positioning) with the file's own styles, composited into the video.
      // Disabled on Android, where libass needs a bundled font asset; there
      // the Flutter [SubtitleView] fallback is used instead.
      libass: defaultTargetPlatform != TargetPlatform.android,
    ),
  );
  late final VideoController _controller = VideoController(_player);

  BrightnessHelper? _brightnessHelper;
  VolumeHelper? _volumeHelper;

  PlaybackProgress? _savedProgress;
  List<DriveItem> _externalSubs = [];

  bool _loading = true;
  AppFailure? _error;
  String? _selectedSubtitleId;
  bool _locked = false;
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
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    // Push the user's subtitle style to libmpv whenever it changes (the
    // editor updates the notifier live while dragging sliders).
    ref.listenManual(subtitleStyleProvider, (previous, next) {
      if (_disposed) return;
      unawaited(_applySubtitleStyleToPlayer(next));
    });
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
        // Checkpoint as soon as the user pauses: the 30 s timer may not have
        // fired yet, and a pause is usually where the session ends.
        _playingSub = _player.stream.playing.listen((playing) {
          if (!playing) _saveProgress();
        });
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
            // mpv surfaces raw strings (expired URL, decoder error); wrap so
            // the screen can show a sentence plus the technical detail.
            _error = PlaybackFailure(detail: error);
            _loading = false;
          });
        });
      }

      // Keep ASS/SSA files' own styles (sub-ass-override=no stops mpv from
      // flattening them to the default sub-* style), then apply the user's
      // style — which affects plain-text subtitles (SRT/VTT) only.
      await _setMpvProperty('sub-ass-override', 'no');
      await _applySubtitleStyleToPlayer(ref.read(subtitleStyleProvider));

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
          _error = AppFailure.from(e);
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
    // A checkpoint every 30 s is enough to survive a crash; writes are whole-
    // blob JSON updates, so the old 5 s cadence was pure disk churn.
    if ((position - _lastSaved).abs() < _progressInterval) return;
    _lastSaved = position;
    _saveProgress();
  }

  /// Persists the current position (no-op when nothing worth resuming).
  void _saveProgress() {
    final position = _player.state.position;
    if (_completed || position <= const Duration(seconds: 3)) return;
    unawaited(
      _progress.save(
        widget.video.id,
        position,
        _player.state.duration,
        name: widget.video.name,
        thumbnailUrl: widget.video.thumbnailUrl,
        size: widget.video.size,
        parentId: widget.video.parentId,
      ),
    );
  }

  void _onDuration(Duration duration) {
    if (_wantsResume && !_resumeSeekDone && duration > Duration.zero) {
      unawaited(_seekToSavedAndPlay());
    }
  }

  /// Seeks to the saved position once, waits for the stream to report the
  /// seek landed, then starts playback. Verifying via the position stream
  /// (instead of fire-and-forget + toast) means a failed seek doesn't get
  /// masked by a "Resumed" message.
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
      await _player.stream.position
          .firstWhere((p) => (p - target).abs() <= tolerance)
          .timeout(timeout);
    } catch (_) {
      // Timeout or stream error — continue anyway.
    }

    if (_disposed || !mounted) return;
    await _player.play();
    if (!mounted) return;
    showSToast(
      context,
      'Resumed from ${formatDuration(target)}',
      bottom: 118,
    );
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    _completed = true;
    unawaited(_progress.clear(widget.video.id));
  }

  // --- Subtitles ----------------------------------------------------------

  /// Low-level libmpv property setter. media_kit only exposes this on the
  /// native player implementation (not the public [Player] API), and the
  /// app only runs libass-rendering builds on native platforms.
  Future<void> _setMpvProperty(String property, String value) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(property, value);
    }
  }

  /// Maps the user's [SubtitleStyle] to libmpv subtitle properties. Only
  /// affects plain-text subtitles (SRT/VTT): with `sub-ass-override=no`,
  /// ASS/SSA files keep their own embedded styles.
  Future<void> _applySubtitleStyleToPlayer(SubtitleStyle style) async {
    if (_disposed) return;
    try {
      // The app's logical font size is referenced to a 1080p window; mpv's
      // sub-font-size is referenced to a 720p window height (scaled with the
      // window when sub-scale-with-window is enabled), hence the 2/3 factor.
      await _setMpvProperty(
        'sub-font-size',
        (style.fontSize * 2 / 3).round().toString(),
      );
      await _setMpvProperty(
        'sub-bold',
        style.fontWeight.value >= 600 ? 'yes' : 'no',
      );
      await _setMpvProperty('sub-color', _toMpvColor(style.color));
      await _setMpvProperty(
        'sub-back-color',
        style.showBackground ? _toMpvColor(style.backgroundColor) : '#00000000',
      );
      await _setMpvProperty(
        'sub-border-size',
        style.outlineEnabled ? style.outlineWidth.toStringAsFixed(2) : '0',
      );
      await _setMpvProperty(
        'sub-border-color',
        _toMpvColor(style.outlineColor),
      );
    } catch (_) {
      // Player not ready yet or already disposed — the style is re-applied
      // on the next open or change, so this is safe to ignore.
    }
  }

  /// Flutter [Color] → mpv `#AARRGGBB` (hex, uppercase).
  static String _toMpvColor(Color color) {
    String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${hex((color.a * 255).round())}'
        '${hex((color.r * 255).round())}'
        '${hex((color.g * 255).round())}'
        '${hex((color.b * 255).round())}';
  }

  /// Subtitle rows for the picker, built from the demuxer's tracks and the
  /// external files found next to the video.
  List<ChoiceGroup> get _subtitleGroups => buildSubtitleChoices(
    embedded: [
      for (final t in _tracks.subtitle)
        (id: t.id, title: t.title, language: t.language),
    ],
    external: _externalSubs,
  );

  /// Every subtitle id the picker can offer (including off/auto), used to
  /// validate a restored preference.
  bool _hasSubtitleChoice(String id) {
    for (final group in _subtitleGroups) {
      for (final choice in group.choices) {
        if (choice.id == id) return true;
      }
    }
    return false;
  }

  Future<void> _applySubtitleId(
    String id, {
    bool silent = false,
    bool persist = true,
  }) async {
    try {
      if (id == subtitleOffId) {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      } else if (id == subtitleAutoId) {
        await _player.setSubtitleTrack(SubtitleTrack.auto());
      } else if (id.startsWith('embedded:')) {
        final target = id.substring('embedded:'.length);
        final track = _firstWhereOrNull(
          _tracks.subtitle,
          (t) => t.id == target,
        );
        if (track == null) {
          throw const PlaybackFailure(
            message: 'That subtitle track is no longer available.',
          );
        }
        await _player.setSubtitleTrack(track);
      } else if (id.startsWith('external:')) {
        final targetId = id.substring('external:'.length);
        final item = _firstWhereOrNull(_externalSubs, (s) => s.id == targetId);
        if (item == null) {
          throw const PlaybackFailure(
            message: 'That subtitle file is no longer available.',
          );
        }
        final url = await ref
            .read(graphServiceProvider)
            .getDownloadUrl(item.id);
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(url, title: item.name),
        );
      }
      if (!mounted) return;
      setState(() => _selectedSubtitleId = id);
      // Remember the choice so re-opening this video restores it. Auto-loads
      // aren't persisted: they re-evaluate on every open (so a newly added
      // Simplified Chinese subtitle wins next time), while explicit user
      // picks stay fixed.
      if (persist) {
        unawaited(_subtitlePref.save(widget.video.id, id));
      }
    } catch (_) {
      if (!mounted) return;
      // Silent restoration failures (stale track id, expired subtitle URL)
      // shouldn't pester the user — fall back to the default silently.
      if (silent) return;
      showSToast(context, 'Could not load subtitle', bottom: 118);
    }
  }

  /// Restores the subtitle choice last saved for this video, or — when the
  /// user never picked one — auto-loads the best matching external subtitle
  /// (Simplified Chinese first). Anything stale or missing is ignored
  /// silently.
  Future<void> _applySavedSubtitle() async {
    final savedId = await _subtitlePref.get(widget.video.id);
    if (!mounted || _disposed) return;

    // The user already picked a subtitle this session (or the restore for a
    // previous open completed) — don't clobber their explicit choice.
    if (_selectedSubtitleId != null) return;

    // No saved preference: auto-load a related external subtitle, preferring
    // Simplified Chinese. Silently skipped when none matches; the pick is
    // not persisted so it re-evaluates on every open.
    if (savedId == null) {
      final auto = _matcher.pickForAutoLoad(widget.video, _externalSubs);
      if (auto != null) {
        await _applySubtitleId(
          externalChoiceId(auto.id),
          silent: true,
          persist: false,
        );
      }
      return;
    }

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

    if (isSubtitleChoiceId(savedId) && _hasSubtitleChoice(savedId)) {
      await _applySubtitleId(savedId, silent: true);
    }
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  // --- Speed --------------------------------------------------------------

  void _onSpeedTap() {
    unawaited(
      showSpeedPicker(
        context,
        currentSpeed: _speed,
        onSelected: (speed) {
          unawaited(_player.setRate(speed));
          setState(() => _speed = speed);
        },
      ),
    );
  }

  // --- Disposal -----------------------------------------------------------

  @override
  void dispose() {
    // Set first so any in-flight async loop (resume confirmation) stops
    // before the player underneath it is disposed.
    _disposed = true;
    // Checkpoint before the player goes away; the write itself is
    // fire-and-forget (SharedPreferences completes on its own).
    _saveProgress();

    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_tracksSub?.cancel());
    unawaited(_trackSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subtitleStyle = ref.watch(subtitleStyleProvider);

    Widget body;
    if (_error != null) {
      body = ErrorState(
        message: _error!.message,
        detail: _error!.detail,
        onRetry: _retry,
      );
    } else if (_loading) {
      body = const LoadingState(label: 'Opening video…');
    } else {
      body = Stack(
        children: [
          // Tight constraints on purpose: left as a loose Stack child the
          // video surface could size itself from the decoded frame (e.g.
          // 1920×1080) and push the control bar off-screen.
          Positioned.fill(
            child: Video(
              controller: _controller,
              fill: AppTheme.playerSurface,
              controls: _locked
                  ? (_) => const SizedBox.shrink()
                  : subtitleVideoControlsBuilder(
                      onSubtitleTap: () => unawaited(_showSubtitlePicker()),
                      onSpeedTap: _onSpeedTap,
                      onAudioTap: _audioTracks.length > 1
                          ? () => unawaited(_showAudioPicker())
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
              child: PlayerLockOverlay(
                onUnlock: () {
                  setState(() => _locked = false);
                },
              ),
            ),
          // Speed badge
          if (!_locked && _speed != 1.0)
            Positioned(
              bottom: 122,
              right: 16,
              child: PlayerSpeedBadge(speed: _speed),
            ),
        ],
      );
    }

    return PopScope(
      child: Scaffold(
        backgroundColor: AppTheme.playerSurface,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            children: [
              body,
              // Always-visible top bar: close button + title
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: PlayerTopBar(
                  title: widget.video.name,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Real audio tracks (excluding the libmpv 'auto'/'no' placeholders).
  List<AudioTrack> get _audioTracks =>
      _tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();

  // --- Desktop keyboard ---------------------------------------------------

  /// Desktop shortcuts, the same set the usual players offer. Taps and drags
  /// on the video keep working; this only adds a keyboard path.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (_loading || _error != null) return KeyEventResult.ignored;

    // Media playback keys.
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      unawaited(_player.playOrPause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeVolume(5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeVolume(-5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      final volume = _player.state.volume;
      unawaited(_player.setVolume(volume > 0 ? 0 : 100));
      _flash(volume > 0 ? 'Muted' : 'Volume 100%');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      unawaited(mk.toggleFullscreen(context));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      unawaited(_showSubtitlePicker());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _seekBy(Duration delta) {
    final duration = _player.state.duration;
    var target = _player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    unawaited(_player.seek(target));
    _flash(
      '${delta.isNegative ? '−' : '+'}${delta.inSeconds.abs()}s  '
      '${formatDuration(target)}',
    );
  }

  void _nudgeVolume(double delta) {
    final next = (_player.state.volume + delta).clamp(0.0, 100.0);
    unawaited(_player.setVolume(next));
    _flash('Volume ${next.round()}%');
  }

  /// Short-lived feedback for keyboard actions, above the control bar.
  void _flash(String text) {
    if (!mounted) return;
    showSToast(context, text, bottom: 118);
  }

  Future<void> _showSubtitlePicker() async {
    final result = await showChoiceDialog(
      context,
      title: 'Subtitles',
      groups: _subtitleGroups,
      selectedId: _selectedSubtitleId,
      appearanceLabel: 'Appearance',
    );
    if (!mounted || result == null) return;
    if (result == choiceDialogAppearance) {
      // The footer action opens the full-screen appearance editor.
      await Navigator.of(context).push<void>(
        SModalPageRoute<void>(
          builder: (_) => const SubtitleStyleEditorPage(),
        ),
      );
      return;
    }
    await _applySubtitleId(result);
  }

  Future<void> _showAudioPicker() async {
    final result = await showChoiceDialog(
      context,
      title: 'Audio track',
      groups: buildAudioChoices([
        for (final t in _audioTracks)
          (id: t.id, title: t.title, language: t.language),
      ]),
      // The row ids are prefixed, so build the same id the choice reports.
      selectedId: audioChoiceId(_currentTrack.audio.id),
    );
    if (!mounted || result == null) return;
    if (result.startsWith('audio:')) {
      unawaited(_applyAudioTrackId(result.substring('audio:'.length)));
    }
  }

  Future<void> _applyAudioTrackId(String trackId) async {
    final track = _firstWhereOrNull(_audioTracks, (t) => t.id == trackId);
    if (track == null) {
      showSToast(context, 'That audio track is no longer available', bottom: 118);
      return;
    }
    try {
      await _player.setAudioTrack(track);
      // _trackSub updates _currentTrack and rebuilds, so the checkmark moves
      // automatically — no manual setState needed.
    } catch (_) {
      if (!mounted) return;
      showSToast(context, 'Could not switch audio track', bottom: 118);
    }
  }
}
