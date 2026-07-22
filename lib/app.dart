import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'providers/auth_provider.dart';
import 'providers/folder_provider.dart';
import 'providers/drive_provider.dart';

class OneDriveVideoApp extends ConsumerWidget {
  const OneDriveVideoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'OneDrive Video',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return switch (auth) {
      Authenticated() => const _PostAuthInitializer(),
      AuthUnauthenticated() ||
      AuthError() ||
      AuthAuthenticating() ||
      AuthInitial() ||
      AuthRestoring() =>
        const LoginPage(),
    };
  }
}

/// Waits for the [FolderNotifier] to load the persisted folder choice, then
/// either shows the [HomePage] (with BrowserPage if a folder was selected) or
/// the [HomePage] with the folder-pick prompt.
class _PostAuthInitializer extends ConsumerWidget {
  const _PostAuthInitializer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(folderProvider);
    // folderProvider starts as null and loads asynchronously.
    // While it's loading we can't distinguish "loading" from "not selected",
    // so we check if the auth state is Authenticated and show a brief loader.
    // In practice the SharedPreferences read is near-instant.
    if (folder != null) {
      // Initialize the drive with the saved root folder (once).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final drive = ref.read(driveProvider);
        if (!drive.isReady) {
          ref.read(driveProvider.notifier).setRoot(
                DriveFolder(folder.id, folder.name),
              );
        }
      });
    }
    return const HomePage();
  }
}