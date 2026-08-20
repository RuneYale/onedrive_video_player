import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/services/subtitle_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/motion.dart';
import '../core/widgets/states.dart';
import '../pages/player_page.dart';
import '../pages/folder_picker_page.dart';
import '../providers/drive_provider.dart';
import '../providers/playback_provider.dart';

class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage({super.key});

  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends ConsumerState<BrowserPage> {
  final FlyoutController _moreController = FlyoutController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final drive = ref.read(driveProvider);
      if (drive.isReady && drive.items.isEmpty && !drive.loading && drive.error == null) {
        unawaited(ref.read(driveProvider.notifier).refresh());
      }
    });
  }

  @override
  void dispose() {
    _moreController.dispose();
    super.dispose();
  }

  Future<void> _openItem(DriveItem item) async {
    if (item.isFolder) {
      await ref.read(driveProvider.notifier).openFolder(item);
    } else if (item.isVideo) {
      final siblings = ref.read(driveProvider).items;
      await Navigator.of(context).push(
        FluentPageRoute<void>(
          builder: (_) => PlayerPage(video: item, siblings: siblings),
        ),
      );
      if (mounted) {
        await ref.read(playbackProgressProvider.notifier).reload();
      }
    }
  }

  Future<void> _clearProgress(DriveItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Clear resume position?'),
        content: Text(
          'Next time you open "${item.name}" it will start from the beginning.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(playbackProgressProvider.notifier).clear(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = ref.watch(driveProvider);
    final progress = ref.watch(playbackProgressProvider);
    final notifier = ref.read(driveProvider.notifier);

    return ScaffoldPage(
      header: PageHeader(
        leading: drive.canGoBack
            ? IconButton(
                icon: const Icon(FluentIcons.back, size: 16),
                onPressed: notifier.goBack,
              )
            : null,
        title: Text(drive.current?.name ?? 'Videos'),
        commandBar: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Change video folder',
              child: IconButton(
                icon: const Icon(FluentIcons.folder_open, size: 18),
                onPressed: () {
                  unawaited(Navigator.of(context).push(
                    FluentPageRoute<void>(
                        builder: (_) => const FolderPickerPage()),
                  ));
                },
              ),
            ),
            Tooltip(
              message: 'Refresh',
              child: IconButton(
                icon: const Icon(FluentIcons.refresh, size: 16),
                onPressed: notifier.refresh,
              ),
            ),
            FlyoutTarget(
              controller: _moreController,
              child: IconButton(
                icon: const Icon(FluentIcons.more, size: 16),
                onPressed: () => _moreController.showFlyout<void>(
                  builder: (context) => MenuFlyout(
                    items: [
                      MenuFlyoutItem(
                        leading: const Icon(FluentIcons.broom, size: 16),
                        text: const Text('Clear all resume positions'),
                        onPressed: () => unawaited(_confirmClearAll()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      content: _Body(
        drive: drive,
        progress: progress,
        onOpen: _openItem,
        onClearProgress: _clearProgress,
        onRetry: notifier.refresh,
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Clear all resume positions?'),
        content: const Text(
          'Every video will start from the beginning next time you open it. This cannot be undone.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(playbackProgressProvider.notifier).clearAll();
    }
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
        icon: FluentIcons.folder_open,
        title: 'This folder is empty',
        message: 'Drop some videos into this folder and refresh.',
        actionLabel: 'Refresh',
        onAction: onRetry,
      );
    }

    // Memoized single-pass matching (see _subCountCache): previously this
    // ran SubtitleMatcher.match per video (O(videos × items)) on every
    // build, including the 5 s progress-provider ticks.
    final subCounts = _subCountCache.of(drive.items);

    return _gridView(drive.items, subCounts);
  }

  Widget _gridView(List<DriveItem> items, Map<String, int> subCounts) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.68,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return FadeSlideIn(
          delay: Duration(milliseconds: (index * 35).clamp(0, 280)),
          child: _GridTile(
            item: item,
            progress: progress[item.id],
            subtitleCount: subCounts[item.id] ?? 0,
            onTap: () => onOpen(item),
            onClearProgress: () => onClearProgress(item),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Grid view tile
// ---------------------------------------------------------------------------

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.item,
    this.progress,
    this.subtitleCount = 0,
    required this.onTap,
    required this.onClearProgress,
  });

  final DriveItem item;
  final PlaybackProgress? progress;
  final int subtitleCount;
  final VoidCallback onTap;
  final VoidCallback onClearProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showResume =
        item.isVideo && progress != null && !progress!.isFinished;

    return Card(
      padding: EdgeInsetsDirectional.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: HoverButton(
          onPressed: onTap,
          onLongPress: showResume ? onClearProgress : null,
          builder: (context, states) {
            final hovered = states.contains(WidgetState.hovered);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GridThumbnail(item: item),
                      if (item.isFolder)
                        Container(
                          color: colors.accent.withValues(alpha: 0.10),
                          alignment: Alignment.center,
                          child: Icon(FluentIcons.folder_fill,
                              size: 48, color: colors.accent),
                        ),
                      if (item.isVideo)
                        const Positioned.fill(
                          child: Center(child: _PlayBadge()),
                        ),
                      if (showResume && progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ProgressBar(
                            value: (progress!.fraction * 100).clamp(0, 100),
                            strokeWidth: 3,
                          ),
                        ),
                      if (subtitleCount > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(FluentIcons.closed_caption,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 2),
                                Text('$subtitleCount',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      // Fluent-style hover highlight wash
                      if (hovered)
                        Positioned.fill(
                          child: ColoredBox(
                            color: colors.onSurface.withValues(alpha: 0.04),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentTheme.of(context)
                              .typography
                              .caption
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                              )),
                      if (showResume && progress != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_formatDuration(Duration(
                            milliseconds:
                                (progress!.positionSeconds * 1000).round(),
                          ))} left off',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (item.isVideo && item.size != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatFileSize(item.size),
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnails
// ---------------------------------------------------------------------------

class _GridThumbnail extends StatelessWidget {
  const _GridThumbnail({required this.item});
  final DriveItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _ThumbnailPlaceholder(colors: colors),
        errorWidget: (_, _, _) => _ThumbnailPlaceholder(colors: colors),
      );
    }
    return _ThumbnailPlaceholder(colors: colors);
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        FluentIcons.video,
        size: 36,
        color: colors.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        FluentIcons.play_solid,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}

String _formatFileSize(int? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}