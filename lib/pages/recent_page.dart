import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/services/playback_progress_service.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/utils/format.dart';
import '../core/widgets/dialogs.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../core/widgets/video_thumb.dart';
import '../providers/playback_provider.dart';
import 'player_page.dart';

/// Recent-play tab: the videos the user has watched, most recent first.
///
/// Each row can be swiped **right** to reveal the remove tray — the Smartisan
/// swipe, not the iOS one — and tapping the tray asks for confirmation.
class RecentPage extends ConsumerStatefulWidget {
  const RecentPage({super.key, this.onBrowseVideos});

  /// Called when the blank view's action is tapped; the shell switches back to
  /// the Videos tab.
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

    final entries = progress.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    final recent = entries.where((e) => e.value.name != null).toList();

    return Column(
      children: [
        SafeArea(bottom: false, child: const SAppBar(title: 'Recent')),
        Expanded(
          child: recent.isEmpty
              ? EmptyState(
                  icon: SGlyphs.history,
                  title: 'No recent plays',
                  message:
                      'Videos you watch will appear here for quick access.',
                  actionLabel: 'Browse videos',
                  onAction: widget.onBrowseVideos,
                )
              : _RecentList(entries: recent),
        ),
      ],
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList({required this.entries});

  final List<MapEntry<String, PlaybackProgress>> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SCardList(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final progress = entry.value;
        return SSwipeRow(
          actionsWidth: 76,
          actions: _RemoveAction(
            onTap: () => unawaited(_clearRecent(context, ref, entry.key)),
          ),
          child: SmartisanTile(
            leading: VideoThumb(url: progress.thumbnailUrl),
            title: Text(
              progress.name!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _RecentSubtitle(progress: progress),
            onTap: () => unawaited(_openRecent(context, ref, entry)),
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
      SPageRoute<void>(
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
    final confirmed = await showSConfirmDialog(
      context,
      title: 'Remove from recent?',
      message: 'This will also clear the resume position for this video.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) {
      await ref.read(playbackProgressProvider.notifier).clear(itemId);
    }
  }
}

/// Position line plus a 2dp accent progress bar under the row title.
class _RecentSubtitle extends StatelessWidget {
  const _RecentSubtitle({required this.progress});

  final PlaybackProgress progress;

  @override
  Widget build(BuildContext context) {
    if (progress.durationSeconds <= 0) {
      return Text(timeAgo(progress.updatedAt));
    }
    final at = Duration(milliseconds: (progress.positionSeconds * 1000).round());
    final total = Duration(
      milliseconds: (progress.durationSeconds * 1000).round(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressLine(value: progress.fraction),
        const SizedBox(height: 4),
        Text(
          '${formatDuration(at)} / ${formatDuration(total)}',
          maxLines: 1,
        ),
      ],
    );
  }
}

/// 2dp track with the accent fill — the kit's slider groove without the thumb.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: Stack(
          children: [
            Container(height: 2, color: p.divider),
            Container(
              height: 2,
              width: constraints.maxWidth * value.clamp(0.0, 1.0),
              color: p.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// The red tray uncovered by a right swipe.
class _RemoveAction extends StatelessWidget {
  const _RemoveAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final red = context.sp.red;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(SGlyphs.trash, size: 20, color: red),
            const SizedBox(height: 2),
            Text(
              'Remove',
              style: TextStyle(fontSize: 10, color: red),
            ),
          ],
        ),
      ),
    );
  }
}
