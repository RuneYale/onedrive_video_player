import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Scriptable [HttpClientAdapter]: queued handlers answer requests in order,
/// and every request is recorded so tests can assert on headers/queries.
class FakeAdapter implements HttpClientAdapter {
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

/// JSON response helper for [FakeAdapter].
Future<ResponseBody> jsonResponse(
  Map<String, dynamic> body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) {
  return Future.value(
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...?headers,
      },
    ),
  );
}

/// Error body in the Graph shape.
Future<ResponseBody> graphError(String code, {int status = 400}) =>
    jsonResponse({
      'error': {'code': code, 'message': 'stub failure'},
    }, status: status);
