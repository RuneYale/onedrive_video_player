import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final drive = ref.read(driveProvider);
      if (drive.isReady && drive.items.isEmpty && !drive.loading && drive.error == null) {
        ref.read(driveProvider.notifier).refresh();
      }
    });
  }

  Future<void> _openItem(DriveItem item) async {
    if (item.isFolder) {
      await ref.read(driveProvider.notifier).openFolder(item);
    } else if (item.isVideo) {
      final siblings = ref.read(driveProvider).items;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerPage(video: item, siblings: siblings),
        ),
      );
      if (mounted) {
        ref.read(playbackProgressProvider.notifier).reload();
      }
    }
  }

  Future<void> _clearProgress(DriveItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('Clear resume position?'),
        content: Text(
          'Next time you open "${item.name}" it will start from the beginning.',
        ),
        actions: [
          TextButton(
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

    return Scaffold(
      appBar: AppBar(
        leading: drive.canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: notifier.goBack,
              )
            : null,
        title: Text(drive.current?.name ?? 'Videos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'Change video folder',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FolderPickerPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: notifier.refresh,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'clearall') {
                _confirmClearAll();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'clearall',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined),
                    SizedBox(width: 12),
                    Text('Clear all resume positions'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _Body(
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
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_outlined),
        title: const Text('Clear all resume positions?'),
        content: const Text(
          'Every video will start from the beginning next time you open it. This cannot be undone.',
        ),
        actions: [
          TextButton(
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
        icon: Icons.folder_open_rounded,
        title: 'This folder is empty',
        message: 'Drop some videos into this folder and refresh.',
        actionLabel: 'Refresh',
        onAction: onRetry,
      );
    }

    const matcher = SubtitleMatcher();
    final subCounts = <String, int>{};
    for (final item in drive.items) {
      if (item.isVideo) subCounts[item.id] = matcher.match(item, drive.items).length;
    }

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: _gridView(drive.items, subCounts),
    );
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
    final scheme = Theme.of(context).colorScheme;
    final showResume =
        item.isVideo && progress != null && !progress!.isFinished;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: showResume ? onClearProgress : null,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _GridThumbnail(item: item),
                  if (item.isFolder)
                    Container(
                      color: scheme.primary.withValues(alpha: 0.10),
                      alignment: Alignment.center,
                      child: Icon(Icons.folder_rounded,
                          size: 48, color: scheme.primary),
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
                      child: LinearProgressIndicator(
                        value: progress!.fraction,
                        minHeight: 3,
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
                            const Icon(Icons.subtitles_rounded,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                        color: scheme.onSurfaceVariant,
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
                        color: scheme.onSurfaceVariant,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ],
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
    final scheme = Theme.of(context).colorScheme;
    if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _ThumbnailPlaceholder(scheme: scheme),
        errorWidget: (_, _, _) => _ThumbnailPlaceholder(scheme: scheme),
      );
    }
    return _ThumbnailPlaceholder(scheme: scheme);
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_rounded,
        size: 36,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
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
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 28,
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