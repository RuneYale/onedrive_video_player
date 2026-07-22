import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/auth_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import '../providers/auth_provider.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: switch (auth) {
                  AuthInitial() || AuthRestoring() =>
                    const LoadingState(label: 'Restoring your session…'),
                  AuthAuthenticating(:final deviceCode) => _DeviceCodeView(
                      deviceCode: deviceCode,
                      onCancel: notifier.cancelSignIn,
                    ),
                  AuthError(:final message) => ErrorState(
                      message: message,
                      onRetry: notifier.signIn,
                    ),
                  AuthUnauthenticated() =>
                    _SignInView(onSignIn: notifier.signIn),
                  Authenticated() => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInView extends StatelessWidget {
  const _SignInView({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final features = <(IconData, String)>[
      (Icons.cloud_done_outlined, 'Stream directly from OneDrive'),
      (Icons.history_rounded, 'Resume where you left off'),
      (Icons.subtitles_outlined, 'External subtitle support'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44),
        ),
        const SizedBox(height: 24),
        Text(
          'OneDrive Video',
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Stream the videos stored in your OneDrive — sign in to browse and play.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 28),
        for (final f in features)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(f.$1, size: 20, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(f.$2, style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in with Microsoft'),
            onPressed: onSignIn,
          ),
        ),
      ],
    );
  }
}

class _DeviceCodeView extends StatefulWidget {
  const _DeviceCodeView({required this.deviceCode, required this.onCancel});
  final DeviceCodeResponse deviceCode;
  final VoidCallback onCancel;

  @override
  State<_DeviceCodeView> createState() => _DeviceCodeViewState();
}

class _DeviceCodeViewState extends State<_DeviceCodeView> {
  late int _remaining;
  Timer? _timer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.deviceCode.expiresIn;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 0) {
        _timer?.cancel();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _remainingLabel {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.deviceCode.userCode));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dc = widget.deviceCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Sign in to Microsoft',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Enter this code on any device to securely sign in.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        _Step(
          index: 1,
          text: 'Open',
          trailing: InkWell(
            onTap: () => launchUrl(Uri.parse(dc.verificationUri)),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dc.verificationUri,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new, size: 16, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Step(
          index: 2,
          text: 'Enter this code',
          trailing: const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        _CodeBox(code: dc.userCode, copied: _copied, onCopy: _copy),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Code expires in $_remainingLabel',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _WaitingRow(),
        const SizedBox(height: 20),
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text, required this.trailing});
  final int index;
  final String text;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
                color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: trailing)),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code, required this.copied, required this.onCopy});
  final String code;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            code,
            style: TextStyle(
              fontSize: 34,
              letterSpacing: 6,
              fontWeight: FontWeight.w700,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
          const SizedBox(width: 14),
          IconButton(
            tooltip: copied ? 'Copied' : 'Copy',
            onPressed: onCopy,
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              color: copied ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Text('Waiting for you to sign in…',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}