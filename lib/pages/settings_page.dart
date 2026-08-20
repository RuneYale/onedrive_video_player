import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/drive_provider.dart';
import '../providers/folder_provider.dart';
import 'folder_picker_page.dart';

/// Settings tab: account info, video folder, subtitle style shortcut,
/// and sign out.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final folder = ref.watch(folderProvider);
    final colors = context.colors;

    final displayName = switch (auth) {
      Authenticated(:final displayName) => displayName,
      _ => null,
    };
    final email = switch (auth) {
      Authenticated(:final email) => email,
      _ => null,
    };

    return ScaffoldPage(
      header: const PageHeader(title: Text('Settings')),
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const _SectionLabel('Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (displayName?.isNotEmpty == true)
                          ? displayName![0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName ?? 'Signed in',
                            style:
                                FluentTheme.of(context).typography.bodyStrong),
                        if (email != null)
                          Text(email,
                              style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Video library'),
          Card(
            padding: EdgeInsetsDirectional.zero,
            child: ListTile(
              leading: Icon(FluentIcons.folder_fill, color: colors.accent),
              title: const Text('Video folder'),
              subtitle: Text(folder?.name ?? 'Not selected'),
              trailing: const Icon(FluentIcons.chevron_right, size: 12),
              onPressed: () => _changeFolder(context),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('About'),
          Card(
            padding: EdgeInsetsDirectional.zero,
            child: ListTile(
              leading: Icon(FluentIcons.info, color: colors.onSurfaceVariant),
              title: const Text('OneDrive Video Player'),
              subtitle: const Text('v1.0.0'),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Button(
              onPressed: () => _confirmSignOut(context, ref),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.sign_out, size: 16, color: colors.error),
                  const SizedBox(width: 8),
                  Text('Sign out', style: TextStyle(color: colors.error)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _changeFolder(BuildContext context) {
    unawaited(Navigator.of(context).push(
      FluentPageRoute<void>(builder: (_) => const FolderPickerPage()),
    ));
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to sign in again to browse your OneDrive videos.'),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Await both so the folder choice and tokens are fully cleared before
      // the auth gate rebuilds into the signed-out state.
      await ref.read(folderProvider.notifier).clear();
      await ref.read(authProvider.notifier).signOut();
      // Drop any cached drive state from the previous account.
      ref.invalidate(driveProvider);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: FluentTheme.of(context).typography.caption?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              )),
    );
  }
}