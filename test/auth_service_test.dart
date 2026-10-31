import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/errors/app_failure.dart';
import 'package:onedrive_video_player/core/models/auth_tokens.dart';
import 'package:onedrive_video_player/core/services/auth_service.dart';
import 'package:onedrive_video_player/core/services/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secret_store.dart';
import 'support/http_fakes.dart';

AuthTokens _expired() => AuthTokens(
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
);

void main() {
  late FakeAdapter adapter;
  late Dio dio;
  late TokenStorage storage;
  late AuthService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = FakeAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    storage = TokenStorage(store: FakeSecretStore());
    service = AuthService(dio, storage);
  });

  tearDown(() => dio.close());

  group('AuthTokens.fromJson', () {
    test('keeps previous refresh token when response omits it', () {
      final t = AuthTokens.fromJson(
        {'access_token': 'a2', 'expires_in': 3600},
        fallbackRefreshToken: 'r1',
      );
      expect(t.refreshToken, 'r1');
    });

    test('prefers rotated refresh token when present', () {
      final t = AuthTokens.fromJson(
        {'access_token': 'a2', 'refresh_token': 'r2', 'expires_in': 3600},
        fallbackRefreshToken: 'r1',
      );
      expect(t.refreshToken, 'r2');
    });

    test('throws FormatException when missing and no fallback', () {
      expect(
        () => AuthTokens.fromJson({'access_token': 'a2', 'expires_in': 3600}),
        throwsFormatException,
      );
    });
  });

  group('AuthService.refresh', () {
    test('single-flight: concurrent calls share one request', () async {
      final gate = Completer<void>();
      adapter.handlers.add((_) async {
        await gate.future;
        return jsonResponse({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'expires_in': 3600,
        });
      });
      final f1 = service.refresh(_expired());
      final f2 = service.refresh(_expired());
      gate.complete();
      final results = await Future.wait([f1, f2]);
      expect(adapter.requests, hasLength(1));
      expect(results[0].accessToken, 'new-access');
      expect(results[1].accessToken, 'new-access');
    });

    test('sequential refreshes issue separate requests', () async {
      for (var i = 0; i < 2; i++) {
        adapter.handlers.add(
          (_) => jsonResponse({'access_token': 'a$i', 'refresh_token': 'r$i'}),
        );
      }
      await service.refresh(_expired());
      await service.refresh(_expired());
      expect(adapter.requests, hasLength(2));
    });

    test('keeps old refresh token when response omits it', () async {
      adapter.handlers.add((_) => jsonResponse({'access_token': 'a2'}));
      final t = await service.refresh(_expired());
      expect(t.refreshToken, 'old-refresh');
    });

    test('throws SessionExpiredException on invalid_grant', () async {
      adapter.handlers.add(
        (_) => jsonResponse(
          {'error': 'invalid_grant', 'error_description': 'token expired'},
          status: 400,
        ),
      );
      await expectLater(
        service.refresh(_expired()),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('AuthService.restore', () {
    test('transient failure keeps the cached session', () async {
      await storage.save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        ),
      );
      await service.restore();
      expect(service.current, isNotNull);
      expect(await storage.load(), isNotNull);
    });

    test('invalid_grant clears the session', () async {
      await storage.save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (_) => jsonResponse({'error': 'invalid_grant'}, status: 400),
      );
      await service.restore();
      expect(service.current, isNull);
      expect(await storage.load(), isNull);
    });

    test('announces the lost session so the UI can sign out', () async {
      await storage.save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (_) => jsonResponse({'error': 'invalid_grant'}, status: 400),
      );
      final expiry = service.sessionExpired.first;
      await service.restore();
      await expectLater(expiry, completes);
    });
  });

  group('AuthService.ensureTokens', () {
    test('drops the dead session when refresh is rejected', () async {
      // The first refresh succeeds but returns immediately-expired tokens
      // (expires_in: 0), so ensureTokens() must refresh again — and that
      // second refresh is rejected with invalid_grant.
      await storage.save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (_) => jsonResponse({'access_token': 'a2', 'expires_in': 0}),
      );
      adapter.handlers.add(
        (_) => jsonResponse({'error': 'invalid_grant'}, status: 400),
      );
      await expectLater(
        service.ensureTokens(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(service.current, isNull);
      expect(await storage.load(), isNull);
    });

    test('forceRefresh rotates only when the token is still the stale one',
        () async {
      await storage.save(
        AuthTokens(
          accessToken: 'current-access',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      // Another request already rotated the token: no refresh should happen.
      final tokens = await service.ensureTokens(
        forceRefresh: true,
        staleAccessToken: 'old-access',
      );
      expect(tokens.accessToken, 'current-access');
      expect(adapter.requests, isEmpty);
    });

    test('throws NotAuthenticatedFailure when there is no session', () async {
      await expectLater(
        service.ensureTokens(),
        throwsA(isA<NotAuthenticatedFailure>()),
      );
    });
  });
}
