import 'dart:async';

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
/// initializes the drive root exactly once before showing [HomePage].
class _PostAuthInitializer extends ConsumerStatefulWidget {
  const _PostAuthInitializer();

  @override
  ConsumerState<_PostAuthInitializer> createState() =>
      _PostAuthInitializerState();
}

class _PostAuthInitializerState extends ConsumerState<_PostAuthInitializer> {
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final folder = ref.watch(folderProvider);
    if (folder != null && !_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final drive = ref.read(driveProvider);
        if (!drive.isReady) {
          unawaited(ref.read(driveProvider.notifier).setRoot(
                DriveFolder(folder.id, folder.name),
              ));
        }
      });
    }
    return const HomePage();
  }
}