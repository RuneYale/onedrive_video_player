import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/states.dart';
import '../pages/browser_page.dart';
import '../pages/folder_picker_page.dart';
import '../pages/recent_page.dart';
import '../pages/settings_page.dart';
import '../providers/folder_provider.dart';

/// Main app shell with a left navigation pane (Videos / Recent / Settings).
///
/// The **Videos** tab shows the browser rooted at the user-selected OneDrive
/// folder. When no folder has been selected yet, a prompt to pick one is shown
/// instead.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final folder = ref.watch(folderProvider);

    return NavigationView(
      pane: NavigationPane(
        selected: _index,
        onChanged: (i) => setState(() => _index = i),
        displayMode: PaneDisplayMode.expanded,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.video),
            title: const Text('Videos'),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.history),
            title: const Text('Recent'),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: const SizedBox.shrink(),
          ),
        ],
      ),
      paneBodyBuilder: (item, body) => IndexedStack(
        index: _index,
        children: [
          // Videos tab
          folder == null ? const _FolderPrompt() : const BrowserPage(),
          // Recent tab
          const RecentPage(),
          // Settings tab
          const SettingsPage(),
        ],
      ),
    );
  }
}

/// Shown on the Videos tab when no root folder has been selected.
class _FolderPrompt extends ConsumerWidget {
  const _FolderPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Videos')),
      content: EmptyState(
        icon: FluentIcons.video,
        title: 'Select a video folder',
        message:
            'Choose a folder from your OneDrive to use as your video library.',
        actionLabel: 'Pick a folder',
        onAction: () {
          unawaited(Navigator.of(context).push(
            FluentPageRoute<void>(builder: (_) => const FolderPickerPage()),
          ));
        },
      ),
    );
  }
}