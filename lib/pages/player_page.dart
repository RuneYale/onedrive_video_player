import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/services/subtitle_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import '../providers/drive_provider.dart';
import '../providers/playback_provider.dart';
import '../widgets/player_gesture_overlay.dart';
import '../widgets/speed_picker.dart';
import '../widgets/subtitle_controls.dart';
import '../widgets/subtitle_style_editor.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.video, this.siblings = const []});

  final DriveItem video;
  final List<DriveItem> siblings;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  late final PlaybackProgressService _progress;
  static const _matcher = SubtitleMatcher();

  bool _loading = true;
  String? _error;

  PlaybackProgress? _savedProgress;
  bool _wantsResume = false;
  bool _resumeSeekDone = false;
  bool _completed = false;

  bool _locked = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Track>? _trackSub;
  DateTime? _lastSave;

  List<DriveItem> _externalSubs = const [];
  Tracks _tracks = const Tracks();
  int _selected = -1;
  String? _loadingSubtitleId;

  /// Whether the floating subtitle selection panel is open over the video.
  bool _subtitlePanelOpen = false;

  /// Whether the floating audio track selection panel is open over the video.
  bool _audioPanelOpen = false;

  /// Currently selected video/audio/subtitle track, kept in sync with
  /// [_player.stream.track] so the audio picker can highlight the active track.
  Track _currentTrack = const Track();

  double _speed = 1.0;

  _PlatformBrightnessHelper? _brightnessHelper;
  _PlatformVolumeHelper? _volumeHelper;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
      ),
    );
    _controller = VideoController(_player);
    _progress = ref.read(playbackProgressServiceProvider);
    if (!Platform.isWindows && !Platform.isLinux) {
      _brightnessHelper = _PlatformBrightnessHelper();
      _volumeHelper = _PlatformVolumeHelper();
    }
    _open();
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

      final url = await ref
          .read(graphServiceProvider)
          .getDownloadUrl(widget.video.id);

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

      await _player.open(Media(url), play: false);

      if (_savedProgress != null) {
        _wantsResume = true;
        if (_player.state.duration > Duration.zero) {
          _seekToSavedAndPlay();
        }
      } else {
        await _player.play();
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onDuration(Duration duration) {
    if (!mounted) return;
    if (_wantsResume &&
        !_resumeSeekDone &&
        duration > Duration.zero &&
        _savedProgress != null) {
      _seekToSavedAndPlay();
    }
  }

  void _seekToSavedAndPlay() {
    if (_savedProgress == null) return;
    _resumeSeekDone = true;
    final position = Duration(
      milliseconds: (_savedProgress!.positionSeconds * 1000).round(),
    );
    _player.seek(position);
    _player.play();
    _showResumeSnackBar(position);
  }

  void _onPosition(Duration position) {
    if (!mounted || _completed) return;
    final now = DateTime.now();
    if (_lastSave == null ||
        now.difference(_lastSave!) >= const Duration(seconds: 5)) {
      _lastSave = now;
      final duration = _player.state.duration;
      if (position > Duration.zero) {
        _progress.save(
          widget.video.id,
          position,
          duration,
          name: widget.video.name,
          thumbnailUrl: widget.video.thumbnailUrl,
          size: widget.video.size,
          parentId: widget.video.parentId,
        );
      }
    }
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    _completed = true;
    _progress.clear(widget.video.id);
  }

  void _showResumeSnackBar(Duration position) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Resumed from ${_formatDuration(position)}'),
        duration: const Duration(seconds: 3),
      ),
    );
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

  Future<void> _applySubtitle(_SubtitleChoice choice) async {
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
            SubtitleTrack.uri(url, title: item.name, language: item.baseName),
          );
      }
      if (!mounted) return;
      final idx = _choices.indexWhere((c) => c.id == choice.id);
      setState(() {
        _selected = idx;
        _loadingSubtitleId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSubtitleId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load subtitle: $e')),
      );
    }
  }

  // --- Speed --------------------------------------------------------------

  void _onSpeedTap() {
    showSpeedPicker(
      context,
      currentSpeed: _speed,
      onSelected: (speed) {
        _player.setRate(speed);
        setState(() => _speed = speed);
      },
    );
  }

  // --- Disposal -----------------------------------------------------------

  @override
  void dispose() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    final shouldSave = !_completed && position > const Duration(seconds: 3);

    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _tracksSub?.cancel();
    _trackSub?.cancel();
    _brightnessHelper?.reset();
    _player.dispose();

    if (shouldSave) {
      _progress.save(
        widget.video.id,
        position,
        duration,
        name: widget.video.name,
        thumbnailUrl: widget.video.thumbnailUrl,
        size: widget.video.size,
        parentId: widget.video.parentId,
      );
    }
    super.dispose();
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = ErrorState(message: _error!);
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
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
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
    final selectedChoice = _selected >= 0 && _selected < choices.length
        ? choices[_selected]
        : null;

    return PopScope(
      canPop: !_anyPanelOpen,
      onPopInvokedWithResult: (didPop, _) {
        // System back closes any open floating panel first instead of leaving
        // the player.
        if (!didPop) _closeAllPanels();
      },
      child: Scaffold(
        backgroundColor: AppTheme.playerSurface,
        body: Focus(
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
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeSubtitlePanel,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 64,
                        right: 16,
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
                    ],
                  ),
                ),
              // Floating audio track selection panel (overlay)
              if (_audioPanelOpen && !_locked)
                Positioned.fill(
                  child: Stack(
                    children: [
                      // Scrim — tap outside the panel to close it.
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeAudioPanel,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 64,
                        right: 16,
                        child: _AudioPanel(
                          tracks: _audioTracks,
                          selected: _currentTrack.audio,
                          onSelected: _applyAudioTrack,
                          onClose: _closeAudioPanel,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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
    await _player.setAudioTrack(track);
    // _trackSub updates _currentTrack and rebuilds the panel, so the
    // checkmark moves automatically — no manual setState needed.
  }

  /// Opens the subtitle appearance editor as a centered dialog (弹窗) rather
  /// than a bottom sheet, keeping it consistent with the floating picker.
  void _showAppearanceEditor(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SubtitleStyleEditor(onClose: () => Navigator.of(ctx).pop()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lock screen overlay
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
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: onClose,
            tooltip: 'Close player',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onUnlock,
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
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
        borderRadius: BorderRadius.circular(8),
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
// Subtitle choices & picker
// ---------------------------------------------------------------------------

sealed class _SubtitleChoice {
  const _SubtitleChoice(this.id, this.label, this.kind);
  final String id;
  final String label;
  final _SubtitleKind kind;
}

class _OffChoice extends _SubtitleChoice {
  const _OffChoice() : super('off', 'Off', _SubtitleKind.off);
}

class _AutoChoice extends _SubtitleChoice {
  const _AutoChoice() : super('auto', 'Auto', _SubtitleKind.auto);
}

class _EmbeddedChoice extends _SubtitleChoice {
  _EmbeddedChoice({required this.track})
      : super(
          'embedded:${track.id}',
          track.title ?? track.language ?? 'Embedded track ${track.id}',
          _SubtitleKind.embedded,
        );
  final SubtitleTrack track;
}

class _ExternalChoice extends _SubtitleChoice {
  _ExternalChoice({required this.item})
      : super('external:${item.id}', item.name, _SubtitleKind.external);
  final DriveItem item;
}

enum _SubtitleKind { off, auto, embedded, external }

const _subtitleLang = SubtitleLanguageResolver();

/// A floating panel that overlays the video for subtitle selection (VLC/MPV
/// style), grouped into Off/Auto, Embedded and External sections. Stays open
/// after a selection so the user can see the checkmark move and try another
/// track; dismissed via the scrim or the close button.
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
    final accent = Theme.of(context).colorScheme.primary;
    const bg = Color(0xF216181F);
    const divider = Color(0x1FFFFFFF);

    final off = choices.whereType<_OffChoice>().toList();
    final auto = choices.whereType<_AutoChoice>().toList();
    final embedded = choices.whereType<_EmbeddedChoice>().toList();
    final external = choices.whereType<_ExternalChoice>().toList();

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
              child: Row(
                children: [
                  Icon(Icons.subtitles_rounded, size: 20, color: accent),
                  const SizedBox(width: 10),
                  const Text('Subtitles',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.white70),
                    onPressed: onClose,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: divider),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final c in [...off, ...auto])
                    _SubtitleRow(
                      choice: c,
                      isSelected: selected?.id == c.id,
                      isLoading: loadingId == c.id,
                      accent: accent,
                      onSelected: onSelected,
                    ),
                  if (embedded.isNotEmpty) ...[
                    const _SectionLabel('Embedded'),
                    for (final c in embedded)
                      _SubtitleRow(
                        choice: c,
                        isSelected: selected?.id == c.id,
                        isLoading: loadingId == c.id,
                        accent: accent,
                        onSelected: onSelected,
                      ),
                  ],
                  if (external.isNotEmpty) ...[
                    const _SectionLabel('External'),
                    for (final c in external)
                      _SubtitleRow(
                        choice: c,
                        video: video,
                        isSelected: selected?.id == c.id,
                        isLoading: loadingId == c.id,
                        accent: accent,
                        onSelected: onSelected,
                      ),
                  ],
                  if (embedded.isEmpty && external.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Text(
                        'No embedded or external subtitles found.\n'
                        'Add an .srt / .vtt / .ass file with a matching name '
                        '(e.g. Movie.en.srt) to see it here.',
                        style: TextStyle(
                            color: Colors.white70, height: 1.5, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: divider),
            InkWell(
              onTap: onCustomize,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.format_size_rounded,
                        size: 20, color: Colors.white70),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Customize appearance',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 1),
                          Text('Size, color, background, outline',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 22, color: Colors.white70),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: Text(text,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          )),
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({
    required this.choice,
    required this.isSelected,
    required this.isLoading,
    required this.accent,
    required this.onSelected,
    this.video,
  });

  final _SubtitleChoice choice;
  final bool isSelected;
  final bool isLoading;
  final Color accent;
  final ValueChanged<_SubtitleChoice> onSelected;

  /// The playing video; only needed for external subtitles to resolve a
  /// language label from the file name.
  final DriveItem? video;

  @override
  Widget build(BuildContext context) {
    final icon = switch (choice.kind) {
      _SubtitleKind.off => Icons.subtitles_off_rounded,
      _SubtitleKind.auto => Icons.auto_awesome_rounded,
      _SubtitleKind.embedded => Icons.movie_filter_outlined,
      _SubtitleKind.external => Icons.closed_caption_rounded,
    };

    String title = choice.label;
    String? subtitle;
    String? formatChip;

    if (choice case _ExternalChoice(:final item)) {
      if (video != null) {
        final lang = _subtitleLang.labelOf(video!, item);
        title = lang ?? item.name;
        subtitle = lang != null ? item.name : null;
      } else {
        title = item.name;
      }
      final ext = item.extension;
      if (ext.isNotEmpty) formatChip = ext.substring(1).toUpperCase();
    } else if (choice case _EmbeddedChoice()) {
      subtitle = 'Embedded track';
    }

    return InkWell(
      onTap: isLoading ? null : () => onSelected(choice),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? accent : Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      )),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (formatChip != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(formatChip,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    )),
              ),
            ],
            const SizedBox(width: 8),
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            else if (isSelected)
              Icon(Icons.check_rounded, color: accent, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audio track selection panel
// ---------------------------------------------------------------------------

/// Floating panel for audio track selection — mirrors [_SubtitlePanel].
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
    final accent = Theme.of(context).colorScheme.primary;
    const bg = Color(0xF216181F);
    const divider = Color(0x1FFFFFFF);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
              child: Row(
                children: [
                  Icon(Icons.audiotrack_rounded, size: 20, color: accent),
                  const SizedBox(width: 10),
                  const Text('Audio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.white70),
                    onPressed: onClose,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: divider),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _AudioRow(
                    track: AudioTrack.auto(),
                    title: 'Auto',
                    subtitle: 'Let the player choose the default track',
                    isSelected: selected.id == 'auto',
                    accent: accent,
                    onSelected: onSelected,
                  ),
                  for (final t in tracks)
                    _AudioRow(
                      track: t,
                      title: _audioTitle(t),
                      subtitle: _audioDetail(t),
                      isDefault: t.isDefault == true,
                      isSelected: selected.id == t.id,
                      accent: accent,
                      onSelected: onSelected,
                    ),
                  if (tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Text(
                        'No audio tracks found.',
                        style: TextStyle(
                            color: Colors.white70, height: 1.5, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.track,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.accent,
    required this.onSelected,
    this.isDefault = false,
  });

  final AudioTrack track;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final bool isDefault;
  final Color accent;
  final ValueChanged<AudioTrack> onSelected;

  @override
  Widget build(BuildContext context) {
    final icon = track.id == 'auto'
        ? Icons.auto_awesome_rounded
        : Icons.audiotrack_rounded;
    return InkWell(
      onTap: () => onSelected(track),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? accent : Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            )),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text('DEFAULT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              )),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected) Icon(Icons.check_rounded, color: accent, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Platform brightness & volume helpers
// ---------------------------------------------------------------------------

class _PlatformBrightnessHelper implements BrightnessHelper {
  double _current = 0.5;
  bool _initialized = false;

  _PlatformBrightnessHelper() {
    _init();
  }

  Future<void> _init() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.app/brightness');
        final value = await platform.invokeMethod<double>('getBrightness');
        if (value != null) {
          _current = value;
          _initialized = true;
        }
      } catch (_) {}
    }
  }

  @override
  double get current => _current;

  @override
  Future<void> set(double value) async {
    _current = value;
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.app/brightness');
        await platform.invokeMethod<void>('setBrightness', {'value': value});
      } catch (_) {}
    }
  }

  Future<void> reset() async {
    if (!_initialized) return;
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.app/brightness');
        await platform.invokeMethod<void>('setBrightness', {'value': 0.5});
      } catch (_) {}
    }
  }
}

class _PlatformVolumeHelper implements VolumeHelper {
  double _current = 0.5;

  _PlatformVolumeHelper() {
    _init();
  }

  Future<void> _init() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.app/volume');
        final value = await platform.invokeMethod<double>('getVolume');
        if (value != null) {
          _current = value;
        }
      } catch (_) {}
    }
  }

  @override
  double get current => _current;

  @override
  Future<void> set(double value) async {
    _current = value;
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.app/volume');
        await platform.invokeMethod<void>('setVolume', {'value': value});
      } catch (_) {}
    }
  }
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

// ---------------------------------------------------------------------------
// Audio track display helpers
// ---------------------------------------------------------------------------

String _audioTitle(AudioTrack t) {
  return t.title ??
      _subtitleLang.nameOfCode(t.language) ??
      t.language ??
      'Track ${t.id}';
}

String _audioChannelsLabel(AudioTrack t) {
  final cc = t.channelscount;
  if (cc != null) {
    return switch (cc) {
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1',
      8 => '7.1',
      _ => '${cc}ch',
    };
  }
  final c = t.channels;
  if (c != null && c.isNotEmpty) return c;
  return '';
}

String? _audioDetail(AudioTrack t) {
  final parts = <String>[];
  // When the title is the track name, show the language separately here.
  if (t.title != null) {
    final ln = _subtitleLang.nameOfCode(t.language) ?? t.language;
    if (ln != null) parts.add(ln);
  }
  final ch = _audioChannelsLabel(t);
  if (ch.isNotEmpty) parts.add(ch);
  if (t.codec != null && t.codec!.isNotEmpty) {
    parts.add(t.codec!.toUpperCase());
  }
  return parts.isEmpty ? null : parts.join(' · ');
}