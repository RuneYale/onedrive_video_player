import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../providers/drive_provider.dart';
import '../providers/folder_provider.dart';

/// Browses the OneDrive folder tree and picks the video-library root.
///
/// Presented as a full-screen page that rises from the bottom: a picker is a
/// modal task, so it doesn't use the drill-down push. Only folders are shown.
class FolderPickerPage extends ConsumerStatefulWidget {
  const FolderPickerPage({super.key});

  @override
  ConsumerState<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends ConsumerState<FolderPickerPage> {
  final List<_PickerFolder> _stack = [];
  List<DriveItem> _items = const [];
  bool _loading = true;
  String? _error;

  bool get _canGoBack => _stack.length > 1;

  @override
  void initState() {
    super.initState();
    _stack.add(const _PickerFolder('root', 'OneDrive'));
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final graph = ref.read(graphServiceProvider);
      final items = await graph.listChildren(_stack.last.id);
      if (!mounted) return;
      setState(() {
        _items = items.where((i) => i.isFolder).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openFolder(DriveItem item) {
    _stack.add(_PickerFolder(item.id, item.name));
    unawaited(_load());
  }

  void _goBack() {
    if (!_canGoBack) return;
    _stack.removeLast();
    unawaited(_load());
  }

  Future<void> _confirm() async {
    final folder = _stack.last;
    await ref
        .read(folderProvider.notifier)
        .select(SelectedFolder(id: folder.id, name: folder.name));
    await ref
        .read(driveProvider.notifier)
        .setRoot(DriveFolder(folder.id, folder.name));
    if (!mounted) return;
    // The caller shows the toast so it lands on a live overlay.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // System back goes up one folder first instead of leaving the picker.
    canPop: !_canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _goBack();
    },
    child: Scaffold(
      backgroundColor: context.sp.page,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SAppBar(
              title: _stack.last.name,
              onBack: () => _canGoBack
                  ? _goBack()
                  : Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(child: _body()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SButton('Use this folder', onPressed: _confirm),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _body() {
    if (_loading) return const LoadingState(label: 'Loading folders…');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return EmptyState(
        icon: SGlyphs.folder,
        title: 'No folders here',
        message:
            'This folder has no sub-folders. Pick another one, or use this '
            'folder as your video library.',
        actionLabel: 'Use this folder',
        onAction: _confirm,
      );
    }
    return SCardList(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return SmartisanTile(
          leading: const Icon(SGlyphs.folder),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _openFolder(item),
        );
      },
    );
  }
}

class _PickerFolder {
  const _PickerFolder(this.id, this.name);
  final String id;
  final String name;
}
