import 'package:flutter/material.dart';

import '../core/models/drive_item.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../core/widgets/video_thumb.dart';

/// Filters the *current folder's* listing by name and returns the chosen item.
///
/// This is deliberately client-side: the browser already has the folder in
/// memory, so search is instant and works offline. Server-side search would
/// need a different Graph query and would not match the folder the user is
/// looking at.
class FolderSearchPage extends StatefulWidget {
  const FolderSearchPage({
    super.key,
    required this.title,
    required this.items,
  });

  /// Folder name, shown in the bar so it is clear what is being searched.
  final String title;
  final List<DriveItem> items;

  @override
  State<FolderSearchPage> createState() => _FolderSearchPageState();
}

class _FolderSearchPageState extends State<FolderSearchPage> {
  String _query = '';

  List<DriveItem> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return [
      for (final item in widget.items)
        if (item.name.toLowerCase().contains(query)) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Scaffold(
      backgroundColor: context.sp.page,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SSearchBar(
              hint: 'Search in ${widget.title}',
              onChanged: (value) => setState(() => _query = value),
              onCancel: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(child: _body(matches)),
        ],
      ),
    );
  }

  Widget _body(List<DriveItem> matches) {
    if (_query.trim().isEmpty) {
      return const EmptyState(
        icon: SGlyphs.search,
        title: 'Search this folder',
        message: 'Type part of a video or folder name.',
      );
    }
    if (matches.isEmpty) {
      return const EmptyState(
        icon: SGlyphs.search,
        title: 'No matches',
        message: 'Try a shorter or different part of the name.',
      );
    }
    return SCardList(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final item = matches[index];
        return SmartisanTile(
          leading: item.isFolder
              ? const Icon(SGlyphs.folder)
              : VideoThumb(url: item.thumbnailUrl),
          title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: item.isFolder
              ? const Text('Folder')
              : Text(item.isVideo ? 'Video' : 'File'),
          onTap: () => Navigator.of(context).pop(item),
        );
      },
    );
  }
}
