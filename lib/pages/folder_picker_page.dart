import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
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
    _load();
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
    _load();
  }

  void _goBack() {
    if (_stack.length > 1) {
      _stack.removeLast();
      _load();
    }
  }

  void _confirm() {
    final folder = _stack.last;
    ref.read(folderProvider.notifier).select(
          SelectedFolder(id: folder.id, name: folder.name),
        );
    ref.read(driveProvider.notifier).setRoot(
          DriveFolder(folder.id, folder.name),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${folder.name}" set as your video folder'),
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canGoBack = _stack.length > 1;

    return Scaffold(
      appBar: AppBar(
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _goBack,
              )
            : null,
        title: Text(_stack.last.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle_rounded),
            tooltip: 'Use this folder',
            onPressed: _confirm,
          ),
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const LoadingState(label: 'Loading folders…');
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.folder_off_rounded,
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
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.video_library_rounded),
              label: Text("Use ' ${_stack.last.name}' as video folder"),
              onPressed: _confirm,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return Card(
                child: InkWell(
                  onTap: () => _openFolder(item),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.folder_rounded,
                              size: 22, color: scheme.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
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