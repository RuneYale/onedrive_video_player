import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/models/auth_tokens.dart';
import 'package:onedrive_video_player/core/services/auth_service.dart';
import 'package:onedrive_video_player/core/services/graph_service.dart';
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

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, [
  String? nextLink,
]) =>
    <String, dynamic>{'value': items, '@odata.nextLink': ?nextLink};

Map<String, dynamic> _file(String id, String name) =>
    <String, dynamic>{'id': id, 'name': name};

Map<String, dynamic> _folder(String id, String name) =>
    <String, dynamic>{'id': id, 'name': name, 'folder': <String, dynamic>{}};

void main() {
  late _FakeAdapter adapter;
  late Dio dio;
  late GraphService graph;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = _FakeAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    final auth = AuthService(dio, const TokenStorage());
    // Seed valid (non-expired) tokens so ensureTokens() needs no network.
    await const TokenStorage().save(
      AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    graph = GraphService(dio, auth);
  });

  tearDown(() => dio.close());

  test('listChildren follows @odata.nextLink and merges all pages', () async {
    adapter.handlers.add(
      (_) => _json(
        _page(
          [_file('a', 'a.mp4')],
          'https://graph.example/next?page=2',
        ),
      ),
    );
    adapter.handlers.add((_) => _json(_page([_file('b', 'b.mp4')])));

    final items = await graph.listChildren('root');

    expect(adapter.requests, hasLength(2));
    expect(items.map((e) => e.name), ['a.mp4', 'b.mp4']);
  });

  test('first page carries \$expand=thumbnails, next pages do not', () async {
    adapter.handlers.add(
      (_) => _json(_page([_file('a', 'a.mp4')], 'https://graph.example/next')),
    );
    adapter.handlers.add((_) => _json(_page([_file('b', 'b.mp4')])));

    await graph.listChildren('root');

    expect(
      adapter.requests[0].uri.queryParameters['\$expand'],
      'thumbnails',
    );
    // @odata.nextLink is followed verbatim: no extra query parameters added.
    expect(adapter.requests[1].uri.toString(), 'https://graph.example/next');
  });

  test('listChildren sorts folders first, then files, case-insensitively',
      () async {
    adapter.handlers.add(
      (_) => _json(
        _page([
          _file('f1', 'alpha.mp4'),
          _folder('d1', 'zeta'),
          _file('f2', 'Bravo.mp4'),
          _folder('d2', 'Alpha'),
        ]),
      ),
    );

    final items = await graph.listChildren('root');

    expect(items.map((e) => e.name), ['Alpha', 'zeta', 'alpha.mp4', 'Bravo.mp4']);
  });
}
