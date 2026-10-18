import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/services/subtitle_service.dart';
import '../core/utils/format.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/widgets/dialogs.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../core/widgets/video_thumb.dart';
import '../providers/drive_provider.dart';
import '../providers/playback_provider.dart';
import 'folder_picker_page.dart';
import 'player_page.dart';

class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage({super.key});

  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends ConsumerState<BrowserPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final drive = ref.read(driveProvider);
      if (drive.isReady &&
          drive.items.isEmpty &&
          !drive.loading &&
          drive.error == null) {
        unawaited(ref.read(driveProvider.notifier).refresh());
      }
    });
  }

  Future<void> _openItem(DriveItem item) async {
    if (item.isFolder) {
      await ref.read(driveProvider.notifier).openFolder(item);
    } else if (item.isVideo) {
      final siblings = ref.read(driveProvider).items;
      await Navigator.of(context).push(
        SPageRoute<void>(
          builder: (_) => PlayerPage(video: item, siblings: siblings),
        ),
      );
      if (mounted) {
        await ref.read(playbackProgressProvider.notifier).reload();
      }
    }
  }

  Future<void> _pickFolder() async {
    final picked = await Navigator.of(context).push<bool>(
      SModalPageRoute<bool>(builder: (_) => const FolderPickerPage()),
    );
    if (picked == true && mounted) {
      showSToast(context, 'Video folder updated');
    }
  }

  Future<void> _clearProgress(DriveItem item) async {
    final confirmed = await showSConfirmDialog(
      context,
      title: 'Clear resume position?',
      message:
          'Next time you open "${item.name}" it will start from the beginning.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (confirmed && mounted) {
      await ref.read(playbackProgressProvider.notifier).clear(item.id);
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showSConfirmDialog(
      context,
      title: 'Clear all resume positions?',
      message:
          'Every video will start from the beginning next time you open it. This cannot be undone.',
      confirmLabel: 'Clear all',
      destructive: true,
    );
    if (confirmed && mounted) {
      await ref.read(playbackProgressProvider.notifier).clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = ref.watch(driveProvider);
    final progress = ref.watch(playbackProgressProvider);
    final notifier = ref.read(driveProvider.notifier);

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: SAppBar(
            title: drive.current?.name ?? 'Videos',
            onBack: drive.canGoBack ? notifier.goBack : null,
            actions: [
              SBarGlyphButton(icon: SGlyphs.folder, onTap: _pickFolder),
              SBarGlyphButton(icon: SGlyphs.refresh, onTap: notifier.refresh),
              Builder(
                builder: (ctx) => SBarGlyphButton(
                  icon: SGlyphs.more,
                  onTap: () => unawaited(
                    showSContextMenu(
                      ctx,
                      width: 260,
                      items: [
                        SMenuItem(
                          'Clear all resume positions',
                          onTap: () => unawaited(_confirmClearAll()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _Body(
            drive: drive,
            progress: progress,
            onOpen: _openItem,
            onClearProgress: _clearProgress,
            onRetry: notifier.refresh,
          ),
        ),
      ],
    );
  }
}

/// Memoizes subtitle-match counts per items-list instance. [_Body.build]
/// reruns whenever the progress provider ticks (every 5 s during playback),
/// but the matching only recomputes when the folder contents actually
/// change (a new list instance).
final _subCountCache = _SubCountCache();

class _SubCountCache {
  List<DriveItem>? _items;
  Map<String, int>? _counts;

  Map<String, int> of(List<DriveItem> items) {
    final cached = _counts;
    if (cached != null && identical(items, _items)) return cached;
    final counts = const SubtitleMatcher().matchCounts(items);
    _items = items;
    _counts = counts;
    return counts;
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.drive,
    required this.progress,
    required this.onOpen,
    required this.onClearProgress,
    required this.onRetry,
  });

  final DriveState drive;
  final Map<String, PlaybackProgress> progress;
  final ValueChanged<DriveItem> onOpen;
  final ValueChanged<DriveItem> onClearProgress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (drive.loading && drive.items.isEmpty) {
      return const LoadingState(label: 'Loading your videos…');
    }
    if (drive.error != null && drive.items.isEmpty) {
      return ErrorState(message: drive.error!, onRetry: onRetry);
    }
    if (drive.items.isEmpty) {
      return EmptyState(
        icon: SGlyphs.folder,
        title: 'This folder is empty',
        message: 'Drop some videos into this folder and refresh.',
        actionLabel: 'Refresh',
        onAction: onRetry,
      );
    }

    // Memoized single-pass matching (see _subCountCache): matching every video
    // against the whole list on each build would be O(videos × items), and
    // _Body rebuilds on the 5 s progress ticks during playback.
    final subCounts = _subCountCache.of(drive.items);

    return SCardList(
      itemCount: drive.items.length,
      itemBuilder: (context, index) {
        final item = drive.items[index];
        final saved = progress[item.id];
        final resumable = item.isVideo && saved != null && !saved.isFinished;
        return SmartisanTile(
          leading: item.isFolder
              ? const Icon(SGlyphs.folder)
              : VideoThumb(url: item.thumbnailUrl),
          title: Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _subtitleFor(item, saved, subCounts[item.id] ?? 0),
          onTap: () => onOpen(item),
          onLongPress: resumable ? () => onClearProgress(item) : null,
        );
      },
    );
  }

  Widget? _subtitleFor(
    DriveItem item,
    PlaybackProgress? saved,
    int subtitleCount,
  ) {
    final parts = <String>[];
    if (item.isVideo && saved != null && !saved.isFinished) {
      final at = Duration(
        milliseconds: (saved.positionSeconds * 1000).round(),
      );
      final total = Duration(
        milliseconds: (saved.durationSeconds * 1000).round(),
      );
      parts.add('Resume ${formatDuration(at)}${total > Duration.zero ? ' of ${formatDuration(total)}' : ''}');
    } else if (item.isVideo && item.size != null) {
      parts.add(formatFileSize(item.size));
    }
    if (subtitleCount > 0) {
      parts.add('$subtitleCount subtitle${subtitleCount == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) return null;
    return Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
