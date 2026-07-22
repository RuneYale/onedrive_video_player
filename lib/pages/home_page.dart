import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/states.dart';
import '../pages/browser_page.dart';
import '../pages/folder_picker_page.dart';
import '../pages/recent_page.dart';
import '../pages/settings_page.dart';
import '../providers/folder_provider.dart';

/// Main app scaffold with a bottom navigation bar (Videos / Recent / Settings).
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

    final pages = <Widget>[
      // Videos tab
      folder == null
          ? const _FolderPrompt()
          : const BrowserPage(),
      // Recent tab
      const RecentPage(),
      // Settings tab
      const SettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: 'Videos',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Recent',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Videos')),
      body: EmptyState(
        icon: Icons.video_library_outlined,
        title: 'Select a video folder',
        message:
            'Choose a folder from your OneDrive to use as your video library.',
        actionLabel: 'Pick a folder',
        onAction: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FolderPickerPage()),
          );
        },
      ),
    );
  }
}