import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/models/auth_tokens.dart';
import 'package:onedrive_video_player/core/services/auth_service.dart';
import 'package:onedrive_video_player/core/services/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scriptable [HttpClientAdapter]: queued handlers answer requests in order.
class _FakeAdapter implements HttpClientAdapter {
  final List<Future<ResponseBody> Function(RequestOptions)> handlers = [];
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (handlers.isEmpty) {
      throw StateError('unexpected request: ${options.uri}');
    }
    return handlers.removeAt(0)(options);
  }

  @override
  void close({bool force = false}) {}
}

Future<ResponseBody> _json(Map<String, dynamic> body, {int status = 200}) {
  return Future.value(
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    ),
  );
}

AuthTokens _expired() => AuthTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

void main() {
  late _FakeAdapter adapter;
  late Dio dio;
  late AuthService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = _FakeAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    service = AuthService(dio, const TokenStorage());
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
        return _json({
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
          (_) => _json({'access_token': 'a$i', 'refresh_token': 'r$i'}),
        );
      }
      await service.refresh(_expired());
      await service.refresh(_expired());
      expect(adapter.requests, hasLength(2));
    });

    test('keeps old refresh token when response omits it', () async {
      adapter.handlers.add((_) => _json({'access_token': 'a2'}));
      final t = await service.refresh(_expired());
      expect(t.refreshToken, 'old-refresh');
    });

    test('throws SessionExpiredException on invalid_grant', () async {
      adapter.handlers.add(
        (_) => _json(
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
      await const TokenStorage().save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        ),
      );
      await service.restore();
      expect(service.current, isNotNull);
      expect(await const TokenStorage().load(), isNotNull);
    });

    test('invalid_grant clears the session', () async {
      await const TokenStorage().save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (_) => _json({'error': 'invalid_grant'}, status: 400),
      );
      await service.restore();
      expect(service.current, isNull);
      expect(await const TokenStorage().load(), isNull);
    });
  });

  group('AuthService.ensureTokens', () {
    test('drops the dead session when refresh is rejected', () async {
      // The first refresh succeeds but returns immediately-expired tokens
      // (expires_in: 0), so ensureTokens() must refresh again — and that
      // second refresh is rejected with invalid_grant.
      await const TokenStorage().save(_expired(), name: 'n', email: 'e');
      adapter.handlers.add(
        (_) => _json({'access_token': 'a2', 'expires_in': 0}),
      );
      adapter.handlers.add(
        (_) => _json({'error': 'invalid_grant'}, status: 400),
      );
      await expectLater(
        service.ensureTokens(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(service.current, isNull);
      expect(await const TokenStorage().load(), isNull);
    });
  });
}
