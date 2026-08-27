import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import 'player_page.dart';
import '../providers/playback_provider.dart';

/// Recent-play tab: shows videos the user has watched, sorted by most recent.
class RecentPage extends ConsumerStatefulWidget {
  const RecentPage({super.key, this.onBrowseVideos});

  /// Called when the empty state's "Browse videos" action is tapped; the
  /// shell ([HomePage]) uses it to switch back to the Videos tab.
  final VoidCallback? onBrowseVideos;

  @override
  ConsumerState<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends ConsumerState<RecentPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(playbackProgressProvider.notifier).reload());
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

    return ScaffoldPage(
      header: const PageHeader(title: Text('Recent')),
      content: recent.isEmpty
          ? EmptyState(
              icon: FluentIcons.history,
              title: 'No recent plays',
              message: 'Videos you watch will appear here for quick access.',
              actionLabel: 'Browse videos',
              onAction: widget.onBrowseVideos,
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final progress = entry.value;
        final colors = context.colors;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Card(
            padding: EdgeInsetsDirectional.zero,
            child: HoverButton(
              onPressed: () => _openRecent(context, ref, entry),
              onLongPress: () => _clearRecent(context, ref, entry.key),
              builder: (context, states) {
                final hovered = states.contains(WidgetState.hovered);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  color: hovered
                      ? colors.onSurface.withValues(alpha: AppAlpha.hoverWash)
                      : Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 80,
                          height: 46,
                          child: progress.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: progress.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(
                                    color: colors.surfaceContainerHigh,
                                  ),
                                  errorWidget: (_, _, _) => Container(
                                    color: colors.surfaceContainerHigh,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      FluentIcons.video,
                                      size: 20,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: colors.surfaceContainerHigh,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    FluentIcons.video,
                                    size: 20,
                                    color: colors.onSurfaceVariant,
                                  ),
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
                            Text(
                              progress.name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentTheme.of(context)
                                  .typography
                                  .bodyStrong,
                            ),
                            const SizedBox(height: 4),
                            if (progress.durationSeconds > 0) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: ProgressBar(
                                  value: (progress.fraction * 100).clamp(
                                    0,
                                    100,
                                  ),
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_fmt(Duration(milliseconds: (progress.positionSeconds * 1000).round()))} / ${_fmt(Duration(milliseconds: (progress.durationSeconds * 1000).round()))}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ] else
                              Text(
                                _timeAgo(progress.updatedAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        FluentIcons.play_solid,
                        size: 16,
                        color: colors.accent,
                      ),
                    ],
                  ),
                );
              },
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
      FluentPageRoute<void>(
        builder: (_) => PlayerPage(video: item, siblings: const []),
      ),
    );
    if (context.mounted) {
      await ref.read(playbackProgressProvider.notifier).reload();
    }
  }

  Future<void> _clearRecent(
    BuildContext context,
    WidgetRef ref,
    String itemId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Remove from recent?'),
        content: const Text(
          'This will also clear the resume position for this video.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: AppTheme.destructiveConfirm(ctx),
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
