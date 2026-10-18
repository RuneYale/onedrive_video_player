import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/smartisan_kit.dart';
import '../core/widgets/dialogs.dart';
import '../providers/auth_provider.dart';
import '../providers/drive_provider.dart';
import '../providers/folder_provider.dart';
import '../widgets/subtitle_style_editor.dart';
import 'folder_picker_page.dart';

/// Settings tab: account, video library, subtitle appearance and sign out —
/// grouped white cards on the real-device pinstripe background.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final folder = ref.watch(folderProvider);

    final displayName = switch (auth) {
      Authenticated(:final displayName) => displayName,
      _ => null,
    };
    final email = switch (auth) {
      Authenticated(:final email) => email,
      _ => null,
    };

    return Column(
      children: [
        SafeArea(bottom: false, child: const SAppBar(title: 'Settings')),
        Expanded(
          child: SmartisanPinstripe(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 30),
              children: [
                SmartisanListSection(
                  header: 'Account',
                  children: [
                    _AccountRow(
                      displayName: displayName,
                      email: email,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SmartisanListSection(
                  header: 'Video library',
                  children: [
                    SmartisanTile(
                      leading: const Icon(SGlyphs.folder),
                      title: const Text('Video folder'),
                      // The folder name goes on its own line so a long
                      // OneDrive path ellipsizes instead of overflowing.
                      subtitle: Text(
                        folder?.name ?? 'Not selected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => unawaited(_changeFolder(context, ref)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SmartisanListSection(
                  header: 'Playback',
                  children: [
                    SmartisanTile(
                      leading: const Icon(SGlyphs.textSize),
                      title: const Text('Subtitle appearance'),
                      onTap: () => unawaited(
                        Navigator.of(context).push<void>(
                          SModalPageRoute<void>(
                            builder: (_) => const SubtitleStyleEditorPage(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SmartisanListSection(
                  header: 'About',
                  children: const [
                    SmartisanTile(
                      leading: Icon(SGlyphs.info),
                      title: Text('OneDrive Video Player'),
                      detail: 'v1.0.0',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SmartisanListSection(
                  children: [
                    SmartisanTile(
                      leading: Icon(SGlyphs.signOut, color: context.sp.red),
                      title: Text(
                        'Sign out',
                        style: TextStyle(color: context.sp.red),
                      ),
                      showChevron: false,
                      onTap: () => unawaited(_confirmSignOut(context, ref)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _changeFolder(BuildContext context, WidgetRef ref) async {
    final picked = await Navigator.of(context).push<bool>(
      SModalPageRoute<bool>(builder: (_) => const FolderPickerPage()),
    );
    if (picked == true && context.mounted) {
      showSToast(context, 'Video folder updated');
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to browse your OneDrive videos.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed) return;
    // Await both so the folder choice and tokens are fully cleared before the
    // auth gate rebuilds into the signed-out state.
    await ref.read(folderProvider.notifier).clear();
    await ref.read(authProvider.notifier).signOut();
    // Drop any cached drive state from the previous account.
    ref.invalidate(driveProvider);
  }
}

/// Signed-in identity: a pale accent disc with the initial, name and address.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.displayName, required this.email});

  final String? displayName;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    final initial = (displayName?.isNotEmpty ?? false)
        ? displayName![0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.blue100),
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: p.accent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName ?? 'Signed in',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: p.title),
                ),
                if (email != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.subtitle),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
