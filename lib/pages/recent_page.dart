import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import 'player_page.dart';
import '../providers/folder_provider.dart';
import '../providers/playback_provider.dart';

/// Recent-play tab: shows videos the user has watched, sorted by most recent.
class RecentPage extends ConsumerStatefulWidget {
  const RecentPage({super.key});

  @override
  ConsumerState<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends ConsumerState<RecentPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackProgressProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(playbackProgressProvider);

    // Sort entries by updatedAt descending
    final entries = progress.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));

    // Only show entries that have a name (i.e. metadata was saved)
    final recent = entries.where((e) => e.value.name != null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Recent')),
      body: recent.isEmpty
          ? EmptyState(
              icon: Icons.history_rounded,
              title: 'No recent plays',
              message: 'Videos you watch will appear here for quick access.',
            )
          : _RecentList(entries: recent),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList({required this.entries});
  final List<MapEntry<String, PlaybackProgress>> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(folderProvider);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final progress = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Card(
            child: InkWell(
              onTap: () => _openRecent(context, ref, entry, folder),
              onLongPress: () => _clearRecent(context, ref, entry.key),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 80,
                        height: 46,
                        child: progress.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: progress.thumbnailUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                ),
                                errorWidget: (_, _, _) => Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.movie_rounded,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.4)),
                                ),
                              )
                            : Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                alignment: Alignment.center,
                                child: Icon(Icons.movie_rounded,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.4)),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title + progress
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(progress.name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          if (progress.durationSeconds > 0) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: progress.fraction,
                                minHeight: 3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_fmt(Duration(
                                milliseconds:
                                    (progress.positionSeconds * 1000).round(),
                              ))} / ${_fmt(Duration(
                                milliseconds:
                                    (progress.durationSeconds * 1000).round(),
                              ))}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontFeatures: AppTheme.tabularFigures,
                              ),
                            ),
                          ] else
                            Text(
                              _timeAgo(progress.updatedAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.play_arrow_rounded,
                        size: 22, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openRecent(
    BuildContext context,
    WidgetRef ref,
    MapEntry<String, PlaybackProgress> entry,
    SelectedFolder? folder,
  ) async {
    final progress = entry.value;
    final item = DriveItem(
      id: entry.key,
      name: progress.name!,
      isFolder: false,
      size: progress.size,
      thumbnailUrl: progress.thumbnailUrl,
      parentId: progress.parentId,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          video: item,
          siblings: const [],
        ),
      ),
    );
    if (context.mounted) {
      ref.read(playbackProgressProvider.notifier).reload();
    }
  }

  Future<void> _clearRecent(
    BuildContext context,
    WidgetRef ref,
    String itemId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('Remove from recent?'),
        content: const Text(
            'This will also clear the resume position for this video.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(playbackProgressProvider.notifier).clear(itemId);
    }
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

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${dt.month}/${dt.day}';
}