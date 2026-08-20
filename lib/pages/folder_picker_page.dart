import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import '../providers/drive_provider.dart';
import '../providers/folder_provider.dart';

/// Lets the user browse their OneDrive folder tree and pick a folder to use
/// as the video library root. Only folders are shown (files are hidden).
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
      // Only show folders
      final folders =
          items.where((i) => i.isFolder).toList();
      if (mounted) {
        setState(() {
          _items = folders;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _openFolder(DriveItem item) {
    _stack.add(_PickerFolder(item.id, item.name));
    unawaited(_load());
  }

  void _goBack() {
    if (_stack.length > 1) {
      _stack.removeLast();
      unawaited(_load());
    }
  }

  void _confirm() {
    final folder = _stack.last;
    unawaited(ref.read(folderProvider.notifier).select(
          SelectedFolder(id: folder.id, name: folder.name),
        ));
    unawaited(ref.read(driveProvider.notifier).setRoot(
          DriveFolder(folder.id, folder.name),
        ));
    // InfoBar is shown from the page below after pop so it isn't clipped by
    // the route transition.
    Navigator.of(context).pop();
    unawaited(displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: Text('"${folder.name}" set as your video folder'),
        severity: InfoBarSeverity.success,
      );
    }, duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _stack.length > 1;

    return PopScope(
      // System back goes up one folder first instead of leaving the picker.
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: ScaffoldPage(
        header: PageHeader(
          leading: canGoBack
              ? Tooltip(
                  message: 'Up one folder',
                  child: IconButton(
                    icon: const Icon(FluentIcons.back, size: 16),
                    onPressed: _goBack,
                  ),
                )
              : null,
          title: Text(_stack.last.name),
          commandBar: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Use this folder',
                child: IconButton(
                  icon: const Icon(FluentIcons.check_mark, size: 16),
                  onPressed: _confirm,
                ),
              ),
              Tooltip(
                message: 'Cancel',
                child: IconButton(
                  icon: const Icon(FluentIcons.chrome_close, size: 14),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        content: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingState(label: 'Loading folders…');
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: FluentIcons.folder_open,
        title: 'No folders here',
        message: 'This folder has no sub-folders. Pick another one or use '
            'this folder as your video library.',
        actionLabel: 'Use this folder',
        onAction: _confirm,
      );
    }

    return Column(
      children: [
        // "Use this folder" banner
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: Button(
              onPressed: _confirm,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.video, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "Use '${_stack.last.name}' as video folder",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final colors = context.colors;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: EdgeInsetsDirectional.zero,
                child: ListTile(
                  onPressed: () => _openFolder(item),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(FluentIcons.folder_fill,
                        size: 20, color: colors.accent),
                  ),
                  title: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(FluentIcons.chevron_right, size: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PickerFolder {
  const _PickerFolder(this.id, this.name);
  final String id;
  final String name;
}