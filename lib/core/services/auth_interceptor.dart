import 'package:dio/dio.dart';

import '../errors/app_failure.dart';
import 'auth_service.dart';

/// Attaches the bearer token to Graph requests and recovers from a 401 by
/// refreshing once and replaying the request.
///
/// Without this, an access token that expires (or is revoked) while the app is
/// open surfaces as a raw error page even though a refresh token is available.
/// The token endpoints themselves are marked [kNoAuthRequest] so the refresh
/// never recurses into this interceptor.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, this._auth);

  final Dio _dio;
  final AuthService _auth;

  /// Guards against a 401 loop: the replayed request is marked, so a second
  /// 401 is surfaced instead of refreshing again.
  static const _retriedKey = 'odvp_auth_retried';

  bool _skip(RequestOptions options) => options.extra[kNoAuthRequest] == true;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_skip(options) || options.headers.containsKey('Authorization')) {
      handler.next(options);
      return;
    }
    try {
      final tokens = await _auth.ensureTokens();
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      handler.next(options);
    } on AppFailure catch (e) {
      handler.reject(_asDio(e, options));
    } catch (e) {
      handler.reject(_asDio(AppFailure.from(e), options));
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final unauthorized = err.response?.statusCode == 401;
    if (!unauthorized || _skip(options) || options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }

    final header = options.headers['Authorization'];
    final staleToken = header is String && header.startsWith('Bearer ')
        ? header.substring('Bearer '.length)
        : null;

    try {
      final tokens = await _auth.ensureTokens(
        forceRefresh: true,
        staleAccessToken: staleToken,
      );
      final retry = options
        ..extra[_retriedKey] = true
        ..headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      handler.resolve(await _dio.fetch<dynamic>(retry));
    } on SessionExpiredException catch (e) {
      // The session is already cleared by AuthService; surface it as an auth
      // failure so the screen can explain what happened.
      handler.reject(
        _asDio(AuthFailure(message: e.message, detail: e.message), options),
      );
    } on AppFailure catch (e) {
      handler.reject(_asDio(e, options));
    } catch (_) {
      handler.next(err);
    }
  }

  DioException _asDio(AppFailure failure, RequestOptions options) =>
      DioException(
        requestOptions: options,
        error: failure,
        type: DioExceptionType.unknown,
      );
}
