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

/// OAuth 2.0 Device Authorization Grant against the Microsoft identity
/// platform, plus silent token refresh.
class AuthService {
  AuthService(this._dio, this._storage);

  final Dio _dio;
  final TokenStorage _storage;

  AuthTokens? _current;
  AuthTokens? get current => _current;

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
  Future<void> restore() async {
    _current = await _storage.load();
    if (_current != null && _current!.isExpired) {
      try {
        _current = await refresh(_current!);
      } catch (_) {
        _current = null;
        await _storage.clear();
      }
    }
  }

  /// Refreshes the access token using the refresh token.
  Future<AuthTokens> refresh(AuthTokens tokens) async {
    final res = await _dio.post<dynamic>(
      AuthConfig.tokenEndpoint,
      data: <String, dynamic>{
        'client_id': AuthConfig.clientId,
        'grant_type': 'refresh_token',
        'refresh_token': tokens.refreshToken,
        'scope': AuthConfig.scopesString,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final refreshed = AuthTokens.fromJson(res.data as Map<String, dynamic>);
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
    if (t.isExpired) return refresh(t);
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
