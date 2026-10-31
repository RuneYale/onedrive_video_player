import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/models/auth_tokens.dart';
import 'package:onedrive_video_player/core/services/secret_store.dart';
import 'package:onedrive_video_player/core/services/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secret_store.dart';

AuthTokens _tokens({
  String access = 'access',
  String refresh = 'refresh',
  DateTime? expiresAt,
}) => AuthTokens(
  accessToken: access,
  refreshToken: refresh,
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
);

void main() {
  late FakeSecretStore secrets;
  late TokenStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets = FakeSecretStore();
    storage = TokenStorage(store: secrets);
  });

  test('round-trips tokens through the secret store', () async {
    await storage.save(_tokens());
    final loaded = await storage.load();
    expect(loaded?.accessToken, 'access');
    expect(loaded?.refreshToken, 'refresh');
  });

  test('never writes tokens to SharedPreferences', () async {
    await storage.save(_tokens(), name: 'Ada', email: 'ada@example.com');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('odvp_access_token'), isNull);
    expect(prefs.getString('odvp_refresh_token'), isNull);
    // The profile is not a secret and stays in plain preferences.
    expect(await storage.userName(), 'Ada');
    expect(await storage.userEmail(), 'ada@example.com');
  });

  test('migrates tokens left in SharedPreferences by an older build', () async {
    SharedPreferences.setMockInitialValues({
      'odvp_access_token': 'legacy-access',
      'odvp_refresh_token': 'legacy-refresh',
      'odvp_expires_at': DateTime.utc(2030).toIso8601String(),
    });

    final loaded = await TokenStorage(store: secrets).load();

    expect(loaded?.accessToken, 'legacy-access');
    expect(loaded?.refreshToken, 'legacy-refresh');
    // Moved to the secret store…
    expect(secrets.values['odvp_access_token'], 'legacy-access');
    // …and removed from the plaintext file.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('odvp_access_token'), isNull);
    expect(prefs.getString('odvp_refresh_token'), isNull);
  });

  test('clear wipes both stores', () async {
    await storage.save(_tokens(), name: 'Ada', email: 'ada@example.com');
    await storage.clear();
    expect(await storage.load(), isNull);
    expect(await storage.userName(), isNull);
    expect(secrets.values, isEmpty);
  });

  test('an unreadable secret store is treated as signed out', () async {
    final broken = TokenStorage(store: _ThrowingSecretStore());
    expect(await broken.load(), isNull);
  });
}

class _ThrowingSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) => Future.error(StateError('keystore down'));

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
