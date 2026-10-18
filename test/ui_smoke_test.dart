import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onedrive_video_player/core/theme/app_theme.dart';
import 'package:onedrive_video_player/core/theme/smartisan_kit.dart';
import 'package:onedrive_video_player/core/widgets/smartisan_extras.dart';
import 'package:onedrive_video_player/pages/home_page.dart';
import 'package:onedrive_video_player/pages/login_page.dart';
import 'package:onedrive_video_player/widgets/subtitle_style_editor.dart';

/// Layout smoke tests: every screen is pumped at a phone width (the kit is
/// drawn for 432dp) and at a desktop window, and any RenderFlex overflow or
/// failed assertion surfaces as a test failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget wrap(Widget home) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );

  Future<void> useSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The login page shows a spinner while the session is restored, so settle
  /// by hand instead of `pumpAndSettle` (a spinner never settles).
  Future<void> settleSession(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final size in const [Size(432, 900), Size(1280, 800)]) {
    testWidgets('login page lays out at $size', (tester) async {
      await useSize(tester, size);
      await tester.pumpWidget(wrap(const LoginPage()));
      await settleSession(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('OneDrive Video'), findsOneWidget);
      expect(find.text('Sign in with Microsoft'), findsOneWidget);
    });

    testWidgets('shell (videos / recent / settings) lays out at $size', (
      tester,
    ) async {
      await useSize(tester, size);
      await tester.pumpWidget(wrap(const HomePage()));
      await settleSession(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Select a video folder'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);

      // Recent tab.
      await tester.tap(find.text('Recent'));
      await settleSession(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('No recent plays'), findsOneWidget);

      // Settings tab.
      await tester.tap(find.text('Settings').last);
      await settleSession(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Subtitle appearance'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });
  }

  testWidgets('subtitle appearance page lays out', (tester) async {
    await useSize(tester, const Size(432, 900));
    await tester.pumpWidget(wrap(const SubtitleStyleEditorPage()));
    await settleSession(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Subtitle appearance'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
  });

  testWidgets('long names ellipsize in the bar and in cards', (tester) async {
    await useSize(tester, const Size(432, 900));
    const long =
        'A very long folder name that would otherwise push the centred title '
        'out of the 48dp bar on a narrow phone';
    await tester.pumpWidget(
      wrap(
        Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: Column(
            children: [
              SafeArea(bottom: false, child: const SAppBar(title: long)),
              Expanded(
                child: SCardList(
                  itemCount: 6,
                  itemBuilder: (context, index) => SmartisanTile(
                    leading: const Icon(SGlyphs.film),
                    title: Text('$long #$index'),
                    subtitle: const Text('1.2 GB · 2 subtitles'),
                    onTap: () {},
                    onLongPress: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1.2 GB'), findsWidgets);
  });
}
