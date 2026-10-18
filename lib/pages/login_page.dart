import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/auth_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/smartisan_kit.dart';
import '../core/widgets/smartisan_extras.dart';
import '../core/widgets/states.dart';
import '../providers/auth_provider.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);

    return Scaffold(
      backgroundColor: context.sp.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 432),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: switch (auth) {
                  AuthInitial() || AuthRestoring() => const LoadingState(
                    label: 'Restoring your session…',
                  ),
                  AuthAuthenticating(:final deviceCode) => _DeviceCodeView(
                    deviceCode: deviceCode,
                    onCancel: notifier.cancelSignIn,
                  ),
                  AuthError(:final message) => ErrorState(
                    message: message,
                    onRetry: notifier.signIn,
                  ),
                  AuthUnauthenticated() => _SignInView(
                    onSignIn: notifier.signIn,
                  ),
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

  static const _features = <(IconData, String)>[
    (SGlyphs.cloud, 'Stream directly from OneDrive'),
    (SGlyphs.history, 'Resume where you left off'),
    (SGlyphs.subtitles, 'External subtitle support'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _AppMark(),
        const SizedBox(height: 18),
        Text(
          'OneDrive Video',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: p.titleOther,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Stream the videos stored in your OneDrive — sign in to browse and play.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: p.body),
        ),
        const SizedBox(height: 24),
        SCard(
          maxWidth: 432,
          child: Column(
            children: [
              for (var i = 0; i < _features.length; i++) ...[
                if (i > 0) const SDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(_features[i].$1, size: 20, color: p.accent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _features[i].$2,
                          style: TextStyle(fontSize: 14, color: p.title),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SButton('Sign in with Microsoft', onPressed: onSignIn),
      ],
    );
  }
}

/// The app mark: a beveled Smartisan-blue tile with the kit's play glyph.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Container(
      width: 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: p.primary,
        borderRadius: BorderRadius.circular(SRadii.sheet),
        border: Border.all(color: p.accentBorder, width: SHair.md),
        boxShadow: p.buttonShadow,
      ),
      // A filled triangle's visual centre sits left of its bounding box, so
      // nudge the glyph a hair to the right.
      child: const Padding(
        padding: EdgeInsets.only(left: 3),
        child: Icon(SGlyphs.play, size: 34, color: Colors.white),
      ),
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
    final p = context.sp;
    final dc = widget.deviceCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in to Microsoft',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: p.titleOther,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter this code on any device to securely sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: p.body),
        ),
        const SizedBox(height: 20),
        SCard(
          maxWidth: 432,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Step(
                  index: 1,
                  text: 'Open the sign-in page',
                  trailing: SButton(
                    'Open',
                    kind: SButtonKind.small,
                    expand: false,
                    onPressed: () =>
                        unawaited(launchUrl(Uri.parse(dc.verificationUri))),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 34, top: 6),
                  child: Text(
                    dc.verificationUri,
                    style: TextStyle(fontSize: 12, color: p.subtitle),
                  ),
                ),
                const SizedBox(height: 18),
                const _Step(index: 2, text: 'Enter this code'),
                const SizedBox(height: 10),
                _CodeWell(
                  code: dc.userCode,
                  copied: _copied,
                  onCopy: _copy,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(SGlyphs.timer, size: 14, color: p.subtitleOther),
                    const SizedBox(width: 6),
                    Text(
                      'Code expires in $_remainingLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: p.subtitle,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: p.accent,
                backgroundColor: p.divider,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Waiting for you to sign in…',
              style: TextStyle(fontSize: 12, color: p.subtitle),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SButton('Cancel', kind: SButtonKind.sheet, onPressed: widget.onCancel),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text, this.trailing});

  final int index;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.blue100),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 16, color: p.title),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _CodeWell extends StatelessWidget {
  const _CodeWell({
    required this.code,
    required this.copied,
    required this.onCopy,
  });

  final String code;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    final radius = BorderRadius.circular(SRadii.md);
    return SInsetShadow(
      shadows: p.insetWellShadow,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: radius,
          border: Border.all(color: p.border, width: SHair.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                code,
                style: TextStyle(
                  fontSize: 30,
                  letterSpacing: 5,
                  fontWeight: FontWeight.w700,
                  color: p.title,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ),
            SBarGlyphButton(
              icon: copied ? SGlyphs.check : SGlyphs.copy,
              size: 20,
              color: copied ? p.accent : p.icon,
              onTap: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}
