import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/errors/app_failure.dart';
import 'package:onedrive_video_player/core/models/auth_tokens.dart';
import 'package:onedrive_video_player/core/services/auth_interceptor.dart';
import 'package:onedrive_video_player/core/services/auth_service.dart';
import 'package:onedrive_video_player/core/services/graph_service.dart';
import 'package:onedrive_video_player/core/services/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secret_store.dart';
import 'support/http_fakes.dart';

Map<String, dynamic> _file(String id, String name) => <String, dynamic>{
  'id': id,
  'name': name,
  'file': <String, dynamic>{'mimeType': 'video/mp4'},
  'size': 1024,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items, [String? next]) =>
    <String, dynamic>{
      'value': items,
      '@odata.nextLink': ?next,
    };

Map<String, dynamic> _folder(String id, String name) =>
    <String, dynamic>{'id': id, 'name': name, 'folder': <String, dynamic>{}};

void main() {
  late FakeAdapter adapter;
  late Dio dio;
  late AuthService auth;
  late GraphService graph;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = FakeAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    final storage = TokenStorage(store: FakeSecretStore());
    // Seed valid (non-expired) tokens so the interceptor needs no refresh.
    await storage.save(
      AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    auth = AuthService(dio, storage);
    dio.interceptors.add(AuthInterceptor(dio, auth));
    graph = GraphService(dio);
  });

  tearDown(() => dio.close());

  test('listChildren follows @odata.nextLink and merges all pages', () async {
    adapter.handlers.add(
      (_) => jsonResponse(
        _page([_file('a', 'a.mp4')], 'https://graph.example/next?page=2'),
      ),
    );
    adapter.handlers.add((_) => jsonResponse(_page([_file('b', 'b.mp4')])));

    final items = await graph.listChildren('root');

    expect(adapter.requests, hasLength(2));
    expect(items.map((e) => e.name), ['a.mp4', 'b.mp4']);
  });

  test('first page projects \$select and expands thumbnails', () async {
    adapter.handlers.add(
      (_) => jsonResponse(
        _page([_file('a', 'a.mp4')], 'https://graph.example/next'),
      ),
    );
    adapter.handlers.add((_) => jsonResponse(_page([_file('b', 'b.mp4')])));

    await graph.listChildren('root');

    final first = adapter.requests[0];
    expect(first.uri.queryParameters['\$expand'], 'thumbnails');
    expect(first.uri.queryParameters['\$select'], contains('name'));
    // The shared Dio's auth interceptor attached the bearer token.
    expect(first.headers['Authorization'], 'Bearer access');
    // @odata.nextLink is followed verbatim: no extra query parameters added.
    expect(adapter.requests[1].uri.toString(), 'https://graph.example/next');
  });

  test('falls back to the unprojected listing when \$select is rejected',
      () async {
    adapter.handlers.add((_) => graphError('invalidRequest', status: 400));
    adapter.handlers.add((_) => jsonResponse(_page([_file('a', 'a.mp4')])));

    final items = await graph.listChildren('root');

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests[0].uri.queryParameters['\$select'], isNotNull);
    expect(adapter.requests[1].uri.queryParameters['\$select'], isNull);
    expect(adapter.requests[1].uri.queryParameters['\$expand'], 'thumbnails');
    expect(items.single.name, 'a.mp4');
  });

  test('listChildren sorts folders first, then files, case-insensitively',
      () async {
    adapter.handlers.add(
      (_) => jsonResponse(
        _page([
          _file('f1', 'alpha.mp4'),
          _folder('d1', 'zeta'),
          _file('f2', 'Bravo.mp4'),
          _folder('d2', 'Alpha'),
        ]),
      ),
    );

    final items = await graph.listChildren('root');

    expect(
      items.map((e) => e.name),
      ['Alpha', 'zeta', 'alpha.mp4', 'Bravo.mp4'],
    );
  });

  test('maps Graph failures to a displayable failure', () async {
    adapter.handlers.add((_) => graphError('itemNotFound', status: 404));

    await expectLater(
      graph.listChildren('gone'),
      throwsA(isA<NotFoundFailure>()),
    );
  });
}
