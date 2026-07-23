import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final scheme = Theme.of(context).colorScheme;

    final displayName = switch (auth) {
      Authenticated(:final displayName) => displayName,
      _ => null,
    };
    final email = switch (auth) {
      Authenticated(:final email) => email,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _SectionLabel('Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
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
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName ?? 'Signed in',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (email != null)
                          Text(email,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Video library'),
          Card(
            child: ListTile(
              leading: Icon(Icons.folder_rounded, color: scheme.primary),
              title: const Text('Video folder'),
              subtitle: Text(folder?.name ?? 'Not selected'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _changeFolder(context),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('About'),
          Card(
            child: ListTile(
              leading: Icon(Icons.info_outline_rounded,
                  color: scheme.onSurfaceVariant),
              title: const Text('OneDrive Video Player'),
              subtitle: const Text('v1.0.0'),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: OutlinedButton.icon(
              icon: Icon(Icons.logout_rounded, color: scheme.error),
              label: Text('Sign out', style: TextStyle(color: scheme.error)),
              onPressed: () => _confirmSignOut(context, ref),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.error.withValues(alpha: 0.3)),
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
      MaterialPageRoute<void>(builder: (_) => const FolderPickerPage()),
    ));
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to sign in again to browse your OneDrive videos.'),
        actions: [
          TextButton(
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
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
    );
  }
}