/// OAuth tokens returned by the Microsoft identity platform.
class AuthTokens {
  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// True when the access token is expired or about to expire (5 min margin).
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  /// Builds tokens from a token endpoint JSON response.
  ///
  /// Per RFC 6749 a refresh response MAY omit `refresh_token`; pass
  /// [fallbackRefreshToken] on the refresh path so the previous refresh
  /// token is kept in that case. Initial token responses must include it.
  factory AuthTokens.fromJson(
    Map<String, dynamic> json, {
    String? fallbackRefreshToken,
  }) {
    final expiresIn =
        int.tryParse(json['expires_in']?.toString() ?? '') ?? 3600;
    final refreshToken =
        (json['refresh_token'] as String?) ?? fallbackRefreshToken;
    if (refreshToken == null) {
      throw const FormatException('token response missing refresh_token');
    }
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  factory AuthTokens.fromMap(Map<String, dynamic> map) => AuthTokens(
        accessToken: map['access_token'] as String,
        refreshToken: map['refresh_token'] as String,
        expiresAt: DateTime.parse(map['expires_at'] as String),
      );

  AuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) =>
      AuthTokens(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}
