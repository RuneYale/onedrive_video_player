import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/services/secret_store_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exercises the DPAPI FFI bindings for real: this runs on the Windows VM that
/// also builds the app, so a wrong struct layout or calling convention fails
/// here instead of at runtime.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'round-trips through DPAPI and keeps the stored value encrypted',
    () async {
      if (!Platform.isWindows) {
        markTestSkipped('DPAPI is Windows-only');
        return;
      }
      const store = WindowsDpapiSecretStore();

      await store.write('token', 'super-secret-access-token');
      expect(await store.read('token'), 'super-secret-access-token');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('odvp_secret_token');
      expect(stored, isNotNull);
      expect(stored, isNot(contains('super-secret')));
      // DPAPI output is binary; the value is kept base64-encoded.
      expect(stored!.length, greaterThan(20));

      await store.delete('token');
      expect(await store.read('token'), isNull);
    },
    skip: !Platform.isWindows,
  );
}
