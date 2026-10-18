import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/smartisan_kit.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../providers/folder_provider.dart';
import 'browser_page.dart';
import 'folder_picker_page.dart';
import 'recent_page.dart';
import 'settings_page.dart';

/// App shell: three Smartisan bottom-navigation tabs — Videos, Recent,
/// Settings — over the flat #F5F5F5 page.
///
/// The **Videos** tab shows the browser rooted at the user-selected OneDrive
/// folder; before one has been picked it shows a blank view with the picker
/// action instead.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;

  Future<void> _pickFolder() async {
    final picked = await Navigator.of(context).push<bool>(
      SModalPageRoute<bool>(builder: (_) => const FolderPickerPage()),
    );
    if (picked == true && mounted) {
      showSToast(context, 'Video folder updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = ref.watch(folderProvider);

    return Scaffold(
      backgroundColor: context.sp.page,
      body: IndexedStack(
        index: _index,
        children: [
          if (folder == null)
            _FolderPrompt(onPick: _pickFolder)
          else
            const BrowserPage(),
          RecentPage(onBrowseVideos: () => setState(() => _index = 0)),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: Container(
        color: context.sp.card,
        child: SafeArea(
          top: false,
          child: SGlyphBottomNav(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: const [
              SNavGlyphItem('Videos', SGlyphs.film),
              SNavGlyphItem('Recent', SGlyphs.history),
              SNavGlyphItem('Settings', SGlyphs.settings),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown on the Videos tab when no root folder has been selected yet.
class _FolderPrompt extends StatelessWidget {
  const _FolderPrompt({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SafeArea(bottom: false, child: const SAppBar(title: 'Videos')),
      Expanded(
        child: EmptyState(
          icon: SGlyphs.folder,
          title: 'Select a video folder',
          message:
              'Choose a folder from your OneDrive to use as your video library.',
          actionLabel: 'Pick a folder',
          onAction: onPick,
        ),
      ),
    ],
  );
}
