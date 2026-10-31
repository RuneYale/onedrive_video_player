import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/errors/app_failure.dart';
import 'package:onedrive_video_player/core/models/auth_tokens.dart';
import 'package:onedrive_video_player/core/services/auth_interceptor.dart';
import 'package:onedrive_video_player/core/services/auth_service.dart';
import 'package:onedrive_video_player/core/services/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secret_store.dart';
import 'support/http_fakes.dart';

AuthTokens _valid([String access = 'access']) => AuthTokens(
  accessToken: access,
  refreshToken: 'refresh',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

void main() {
  late FakeAdapter adapter;
  late Dio dio;
  late TokenStorage storage;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = FakeAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    storage = TokenStorage(store: FakeSecretStore());
    auth = AuthService(dio, storage);
    dio.interceptors.add(AuthInterceptor(dio, auth));
  });

  tearDown(() => dio.close());

  test('attaches the bearer token', () async {
    await storage.save(_valid());
    adapter.handlers.add((_) => jsonResponse({'ok': true}));

    await dio.get<dynamic>('https://graph.example/me');

    expect(adapter.requests.single.headers['Authorization'], 'Bearer access');
  });

  test('401 refreshes once and replays the request', () async {
    await storage.save(_valid('old'));
    adapter.handlers.add(
      (_) => jsonResponse({'error': 'InvalidAuthenticationToken'}, status: 401),
    );
    adapter.handlers.add(
      (_) => jsonResponse({
        'access_token': 'new',
        'refresh_token': 'r2',
        'expires_in': 3600,
      }),
    );
    adapter.handlers.add((_) => jsonResponse({'ok': true}));

    final res = await dio.get<dynamic>('https://graph.example/me');

    expect(res.data, {'ok': true});
    expect(adapter.requests, hasLength(3));
    expect(adapter.requests[2].headers['Authorization'], 'Bearer new');
  });

  test('a second 401 surfaces instead of refreshing again', () async {
    await storage.save(_valid('old'));
    adapter.handlers.add((_) => jsonResponse({'e': 1}, status: 401));
    adapter.handlers.add(
      (_) => jsonResponse({
        'access_token': 'new',
        'refresh_token': 'r2',
        'expires_in': 3600,
      }),
    );
    adapter.handlers.add((_) => jsonResponse({'e': 2}, status: 401));

    await expectLater(
      dio.get<dynamic>('https://graph.example/me'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(3));
  });

  test('a dead refresh token clears the session and rejects with AuthFailure',
      () async {
    await storage.save(_valid('old'));
    adapter.handlers.add((_) => jsonResponse({'e': 1}, status: 401));
    adapter.handlers.add(
      (_) => jsonResponse({'error': 'invalid_grant'}, status: 400),
    );

    final expiry = auth.sessionExpired.first;
    await expectLater(
      dio.get<dynamic>('https://graph.example/me'),
      throwsA(
        isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<AuthFailure>(),
        ),
      ),
    );
    await expectLater(expiry, completes);
    expect(await storage.load(), isNull);
  });

  test('token requests bypass the interceptor', () async {
    adapter.handlers.add(
      (_) => jsonResponse({
        'device_code': 'dc',
        'user_code': 'uc',
        'verification_uri': 'https://example/device',
        'expires_in': 900,
        'interval': 5,
      }),
    );

    final code = await auth.requestDeviceCode();

    expect(code.userCode, 'uc');
    expect(adapter.requests.single.headers['Authorization'], isNull);
  });
}
