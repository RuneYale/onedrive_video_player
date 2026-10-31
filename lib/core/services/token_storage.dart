import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_tokens.dart';
import 'secret_store.dart';

/// Persists auth tokens and the signed-in user's profile locally so the user
/// stays signed in across app restarts.
///
/// Tokens live in [SecretStore] (Keystore / DPAPI), never in the plain
/// preferences file. The display name and e-mail are not secrets and stay in
/// SharedPreferences so the account row can render without touching the
/// keystore.
///
/// Versions before this one kept the tokens in SharedPreferences; [load]
/// migrates them on first run and deletes the plaintext copies.
class TokenStorage {
  const TokenStorage({SecretStore store = const PlatformSecretStore()})
    : _secrets = store;

  final SecretStore _secrets;

  // Same key names as the legacy SharedPreferences entries; the prefix keeps
  // the secure store self-describing.
  static const _kAccessToken = 'odvp_access_token';
  static const _kRefreshToken = 'odvp_refresh_token';
  static const _kExpiresAt = 'odvp_expires_at';
  static const _kUserName = 'odvp_user_name';
  static const _kUserEmail = 'odvp_user_email';

  Future<void> save(
    AuthTokens tokens, {
    String? name,
    String? email,
  }) async {
    await _writeSecrets(
      tokens.accessToken,
      tokens.refreshToken,
      tokens.expiresAt,
    );
    if (name == null && email == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString(_kUserName, name);
    if (email != null) await prefs.setString(_kUserEmail, email);
  }

  Future<AuthTokens?> load() async {
    final fromSecrets = await _readSecrets();
    if (fromSecrets != null) return fromSecrets;
    // First run after the secure-storage upgrade: move the plaintext tokens
    // over and remove them from SharedPreferences.
    return _migrateLegacyTokens();
  }

  Future<String?> userName() async =>
      (await SharedPreferences.getInstance()).getString(_kUserName);

  Future<String?> userEmail() async =>
      (await SharedPreferences.getInstance()).getString(_kUserEmail);

  Future<void> clear() async {
    // Legacy copies may still exist if the app was killed mid-migration.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserEmail);
    await _deleteSecrets();
  }

  // --- secure storage -----------------------------------------------------

  Future<AuthTokens?> _readSecrets() async {
    try {
      final access = await _secrets.read(_kAccessToken);
      final refresh = await _secrets.read(_kRefreshToken);
      final expiresAt = await _secrets.read(_kExpiresAt);
      if (access == null || refresh == null || expiresAt == null) return null;
      return AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.parse(expiresAt),
      );
    } catch (_) {
      // Unreadable/corrupt secure store: treat as signed out rather than
      // failing the app start. The next sign-in rewrites it.
      return null;
    }
  }

  Future<void> _writeSecrets(
    String access,
    String refresh,
    DateTime expiresAt,
  ) async {
    await _secrets.write(_kAccessToken, access);
    await _secrets.write(_kRefreshToken, refresh);
    await _secrets.write(_kExpiresAt, expiresAt.toIso8601String());
  }

  Future<void> _deleteSecrets() async {
    await _secrets.delete(_kAccessToken);
    await _secrets.delete(_kRefreshToken);
    await _secrets.delete(_kExpiresAt);
  }

  Future<AuthTokens?> _migrateLegacyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccessToken);
    final refresh = prefs.getString(_kRefreshToken);
    final expiresAt = prefs.getString(_kExpiresAt);
    if (access == null || refresh == null || expiresAt == null) return null;

    final parsed = DateTime.tryParse(expiresAt);
    if (parsed == null) {
      await prefs.remove(_kAccessToken);
      await prefs.remove(_kRefreshToken);
      await prefs.remove(_kExpiresAt);
      return null;
    }

    await _writeSecrets(access, refresh, parsed);
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiresAt);
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: parsed,
    );
  }
}
