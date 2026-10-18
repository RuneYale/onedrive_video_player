import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/drive_item.dart';
import '../core/models/subtitle_style.dart';
import '../core/services/playback_progress_service.dart';
import '../core/services/subtitle_preference_service.dart';
import '../core/services/subtitle_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/utils/format.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../providers/drive_provider.dart';
import '../providers/subtitle_style_provider.dart';
import '../widgets/player_gesture_overlay.dart';
import '../widgets/speed_picker.dart';
import '../widgets/subtitle_controls.dart';
import '../widgets/subtitle_style_editor.dart';

/// Sent by the subtitle dialog's appearance action.
const _kAppearanceAction = 'appearance';

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
  String? _error;
  String? _selectedSubtitleId;
  String? _loadingSubtitleId;
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
    }
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

  List<_SubtitleChoice> get _choices {
    final list = <_SubtitleChoice>[const _OffChoice(), const _AutoChoice()];
    for (final t in _tracks.subtitle) {
      if (t.id == 'auto' || t.id == 'no') continue;
      list.add(_EmbeddedChoice(track: t));
    }
    for (final s in _externalSubs) {
      list.add(_ExternalChoice(item: s));
    }
    return list;
  }

  Future<void> _applySubtitle(
    _SubtitleChoice choice, {
    bool silent = false,
    bool persist = true,
  }) async {
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
          final url = await ref
              .read(graphServiceProvider)
              .getDownloadUrl(item.id);
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(url, title: item.name),
          );
      }
      if (!mounted) return;
      setState(() {
        _selectedSubtitleId = choice.id;
        _loadingSubtitleId = null;
      });
      // Remember the choice so re-opening this video restores it. Auto-loads
      // aren't persisted: they re-evaluate on every open (so a newly added
      // Simplified Chinese subtitle wins next time), while explicit user
      // picks stay fixed.
      if (persist) {
        unawaited(_subtitlePref.save(widget.video.id, choice.id));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSubtitleId = null);
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
        for (final c in _choices) {
          if (c is _ExternalChoice && c.item.id == auto.id) {
            await _applySubtitle(c, silent: true, persist: false);
            break;
          }
        }
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
      unawaited(
        _progress.save(
          widget.video.id,
          position,
          duration,
          name: widget.video.name,
          thumbnailUrl: widget.video.thumbnailUrl,
          size: widget.video.size,
          parentId: widget.video.parentId,
        ),
      );
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
              child: _LockScreen(
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
              child: _SpeedBadge(speed: _speed),
            ),
        ],
      );
    }

    return PopScope(
      child: Scaffold(
        backgroundColor: AppTheme.playerSurface,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              body,
              // Always-visible top bar: close button + title
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(
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

  Future<void> _showSubtitlePicker() async {
    final choices = _choices;
    final selectedId = _selectedSubtitleId;

    final groups = <String, List<_SubtitleChoice>>{
      'State': [
        for (final c in choices)
          if (c is _OffChoice || c is _AutoChoice) c,
      ],
      'Embedded tracks': [
        for (final c in choices)
          if (c is _EmbeddedChoice) c,
      ],
      'External subtitles': [
        for (final c in choices)
          if (c is _ExternalChoice) c,
      ],
    };

    final result = await _showChoiceDialog(
      title: 'Subtitles',
      selectedId: selectedId,
      groups: groups,
      footer: 'Appearance',
    );
    if (!mounted || result == null) return;
    if (result is String) {
      // The footer action: open the full-screen appearance editor.
      if (result == _kAppearanceAction) {
        await Navigator.of(context).push<void>(
          SModalPageRoute<void>(
            builder: (_) => const SubtitleStyleEditorPage(),
          ),
        );
      }
      return;
    }
    await _applySubtitle(result as _SubtitleChoice);
  }

  Future<void> _showAudioPicker() async {
    final tracks = _audioTracks;
    // The row ids are prefixed, so build the same id the choice reports.
    final selectedId = 'audio:${_currentTrack.audio.id}';
    final result = await _showChoiceDialog(
      title: 'Audio track',
      selectedId: selectedId,
      groups: {
        'Tracks': [
          for (final t in tracks) _AudioChoice(track: t),
        ],
      },
      footer: null,
    );
    if (!mounted || result == null) return;
    if (result is _AudioChoice) {
      unawaited(_applyAudioTrack(result.track));
    }
  }

  /// One dialog for both pickers: a flush white list of 48dp rows whose
  /// pressed fill is the dialog button grey, and a 54dp action row.
  Future<Object?> _showChoiceDialog({
    required String title,
    required String? selectedId,
    required Map<String, List<_Choice>> groups,
    required String? footer,
  }) {
    final rows = <Widget>[];
    for (final entry in groups.entries) {
      final items = entry.value;
      if (items.isEmpty) continue;
      if (rows.isNotEmpty) rows.add(const SDivider(indent: 16));
      rows.add(_GroupLabel(entry.key));
      for (var i = 0; i < items.length; i++) {
        final choice = items[i];
        rows.add(
          _ChoiceRow(
            icon: choice.icon,
            label: choice.label,
            selected: choice.id == selectedId,
            loading: choice.id == _loadingSubtitleId,
            onTap: () => Navigator.of(context, rootNavigator: true).pop(
              choice,
            ),
          ),
        );
        if (i < items.length - 1) rows.add(const SDivider(indent: 16));
      }
    }

    return Navigator.of(context, rootNavigator: true).push<Object?>(
      SDialogRoute<Object?>(
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
                if (footer != null)
                  SDialogButton(
                    footer,
                    onTap: () => Navigator.of(ctx).pop(_kAppearanceAction),
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

  Future<void> _applyAudioTrack(AudioTrack track) async {
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

// ---------------------------------------------------------------------------
// Dialog rows
// ---------------------------------------------------------------------------

/// Header of a group inside the choice dialog.
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
    required this.icon,
    required this.label,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool loading;
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
            Icon(icon, size: 18, color: selected ? p.accent : p.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
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
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.accent,
                ),
              )
            else if (selected)
              Icon(SGlyphs.check, size: 16, color: p.accent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtitle / audio choices
// ---------------------------------------------------------------------------

sealed class _Choice {
  const _Choice();
  String get id;
  String get label;
  IconData get icon;
}

sealed class _SubtitleChoice extends _Choice {
  const _SubtitleChoice();
}

class _OffChoice extends _SubtitleChoice {
  const _OffChoice();
  @override
  String get id => 'off';
  @override
  String get label => 'Off';
  @override
  IconData get icon => SGlyphs.close;
}

class _AutoChoice extends _SubtitleChoice {
  const _AutoChoice();
  @override
  String get id => 'auto';
  @override
  String get label => 'Auto';
  @override
  IconData get icon => SGlyphs.sparkle;
}

class _EmbeddedChoice extends _SubtitleChoice {
  const _EmbeddedChoice({required this.track});
  final SubtitleTrack track;
  @override
  String get id => 'embedded:${track.id}';
  @override
  String get label => track.title ?? track.language ?? 'Track ${track.id}';
  @override
  IconData get icon => SGlyphs.subtitles;
}

class _ExternalChoice extends _SubtitleChoice {
  const _ExternalChoice({required this.item});
  final DriveItem item;
  @override
  String get id => 'external:${item.id}';
  @override
  String get label => item.name;
  @override
  IconData get icon => SGlyphs.file;
}

class _AudioChoice extends _Choice {
  const _AudioChoice({required this.track});
  final AudioTrack track;
  @override
  String get id => 'audio:${track.id}';
  @override
  String get label => track.title ?? track.language ?? 'Track ${track.id}';
  @override
  IconData get icon => SGlyphs.headphones;
}
