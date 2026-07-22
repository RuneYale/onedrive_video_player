import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_tokens.dart';

/// Persists auth tokens and the signed-in user's profile locally so the
/// user stays signed in across app restarts.
class TokenStorage {
  const TokenStorage();

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, tokens.accessToken);
    await prefs.setString(_kRefreshToken, tokens.refreshToken);
    await prefs.setString(_kExpiresAt, tokens.expiresAt.toIso8601String());
    if (name != null) await prefs.setString(_kUserName, name);
    if (email != null) await prefs.setString(_kUserEmail, email);
  }

  Future<AuthTokens?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccessToken);
    final refresh = prefs.getString(_kRefreshToken);
    final exp = prefs.getString(_kExpiresAt);
    if (access == null || refresh == null || exp == null) return null;
    try {
      return AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.parse(exp),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> userName() async =>
      (await SharedPreferences.getInstance()).getString(_kUserName);

  Future<String?> userEmail() async =>
      (await SharedPreferences.getInstance()).getString(_kUserEmail);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserEmail);
  }
}
