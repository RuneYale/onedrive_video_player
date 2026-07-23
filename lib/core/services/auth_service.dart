import 'package:dio/dio.dart';

import '../../config/auth_config.dart';
import '../models/auth_tokens.dart';
import 'token_storage.dart';

/// Response from the device-code authorization request.
class DeviceCodeResponse {
  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
    this.message,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
  final String? message;

  factory DeviceCodeResponse.fromJson(Map<String, dynamic> json) =>
      DeviceCodeResponse(
        deviceCode: json['device_code'] as String,
        userCode: json['user_code'] as String,
        verificationUri: json['verification_uri'] as String,
        expiresIn: (json['expires_in'] as num).toInt(),
        interval: (json['interval'] as num?)?.toInt() ?? 5,
        message: json['message'] as String?,
      );
}

/// Result of a successful sign-in: tokens + basic profile.
class AuthResult {
  const AuthResult({required this.tokens, this.displayName, this.email});
  final AuthTokens tokens;
  final String? displayName;
  final String? email;
}

class DeviceCodePendingException implements Exception {}
class DeviceCodeSlowDownException implements Exception {}

class DeviceCodeExpiredException implements Exception {
  const DeviceCodeExpiredException(this.message);
  final String message;
}

class DeviceCodeDeniedException implements Exception {}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when the token endpoint rejects the refresh token
/// (`invalid_grant` / `interaction_required`): the session is
/// unrecoverable and must be cleared. Any other refresh failure
/// (offline, timeout, 5xx) is transient and must NOT clear the session.
class SessionExpiredException extends AuthException {
  const SessionExpiredException(super.message);
}

/// OAuth 2.0 Device Authorization Grant against the Microsoft identity
/// platform, plus silent token refresh.
class AuthService {
  AuthService(this._dio, this._storage);

  final Dio _dio;
  final TokenStorage _storage;

  AuthTokens? _current;
  AuthTokens? get current => _current;

  /// In-flight refresh, so concurrent callers share a single request.
  /// Microsoft rotates refresh tokens, so parallel refreshes with the same
  /// refresh token can overwrite `_current` with a superseded token or even
  /// trigger token-family revocation.
  Future<AuthTokens>? _refreshing;

  /// Requests a device code that the user must authorize in a browser.
  Future<DeviceCodeResponse> requestDeviceCode() async {
    final res = await _dio.post<dynamic>(
      AuthConfig.deviceCodeEndpoint,
      data: <String, dynamic>{
        'client_id': AuthConfig.clientId,
        'scope': AuthConfig.scopesString,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return DeviceCodeResponse.fromJson(res.data as Map<String, dynamic>);
  }
  /// Polls the token endpoint once. Throws [DeviceCodePendingException]
  /// while waiting, or other device-code exceptions on failure.
  Future<AuthResult> pollForToken(String deviceCode) async {
    try {
      final res = await _dio.post<dynamic>(
        AuthConfig.tokenEndpoint,
        data: <String, dynamic>{
          'client_id': AuthConfig.clientId,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': deviceCode,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final tokens = AuthTokens.fromJson(res.data as Map<String, dynamic>);
      _current = tokens;
      final profile = await _fetchProfile(tokens.accessToken);
      final result = AuthResult(
        tokens: tokens,
        displayName: profile?['displayName'] as String?,
        email: (profile?['mail'] as String?) ??
            (profile?['userPrincipalName'] as String?),
      );
      await _storage.save(
        tokens,
        name: result.displayName,
        email: result.email,
      );
      return result;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final error = data['error'];
        switch (error) {
          case 'authorization_pending':
            throw DeviceCodePendingException();
          case 'slow_down':
            throw DeviceCodeSlowDownException();
          case 'expired_token':
            throw DeviceCodeExpiredException(
              (data['error_description'] as String?) ?? 'expired',
            );
          case 'access_denied':
          case 'authorization_declined':
            throw DeviceCodeDeniedException();
          default:
            throw AuthException(
              data['error_description'] as String? ??
                  e.message ??
                  'auth error',
            );
        }
      }
      throw AuthException(e.message ?? 'network error');
    }
  }

  /// Loads cached tokens and refreshes them if expired.
  ///
  /// The stored session is cleared ONLY when the server rejects the
  /// refresh token ([SessionExpiredException]). Transient failures
  /// (offline, timeout, 5xx) keep the cached session so the user stays
  /// signed in; [ensureTokens] retries the refresh on the next API call.
  Future<void> restore() async {
    _current = await _storage.load();
    if (_current != null && _current!.isExpired) {
      try {
        _current = await refresh(_current!);
      } on SessionExpiredException {
        _current = null;
        await _storage.clear();
      } catch (_) {
        // Transient refresh failure: keep the cached session.
      }
    }
  }

  /// Refreshes the access token using the refresh token.
  ///
  /// Concurrent callers share a single in-flight request (single-flight);
  /// see [_refreshing].
  Future<AuthTokens> refresh(AuthTokens tokens) {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    return _refreshing = _doRefresh(tokens).whenComplete(() {
      _refreshing = null;
    });
  }

  Future<AuthTokens> _doRefresh(AuthTokens tokens) async {
    final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        AuthConfig.tokenEndpoint,
        data: <String, dynamic>{
          'client_id': AuthConfig.clientId,
          'grant_type': 'refresh_token',
          'refresh_token': tokens.refreshToken,
          'scope': AuthConfig.scopesString,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final error = data['error'];
        if (error == 'invalid_grant' || error == 'interaction_required') {
          throw SessionExpiredException(
            (data['error_description'] as String?) ??
                'The sign-in session has expired.',
          );
        }
      }
      rethrow;
    }
    final refreshed = AuthTokens.fromJson(
      res.data as Map<String, dynamic>,
      // RFC 6749 allows a refresh response to omit `refresh_token`; keep
      // the previous one in that case instead of throwing mid-refresh.
      fallbackRefreshToken: tokens.refreshToken,
    );
    _current = refreshed;
    final name = await _storage.userName();
    final email = await _storage.userEmail();
    await _storage.save(refreshed, name: name, email: email);
    return refreshed;
  }

  /// Returns valid (non-expired) tokens, refreshing if necessary.
  /// Throws [StateError] when there is no signed-in account.
  Future<AuthTokens> ensureTokens() async {
    if (_current == null) await restore();
    final t = _current;
    if (t == null) throw StateError('Not authenticated');
    if (t.isExpired) {
      try {
        return await refresh(t);
      } on SessionExpiredException {
        // The refresh token is dead — drop the session so the app falls
        // back to signed-out instead of retrying with a dead token.
        await signOut();
        rethrow;
      }
    }
    return t;
  }

  Future<void> signOut() async {
    _current = null;
    await _storage.clear();
  }

  Future<Map<String, dynamic>?> _fetchProfile(String accessToken) async {
    try {
      final res = await _dio.get<dynamic>(
        '${AuthConfig.graphBase}/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return res.data as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
