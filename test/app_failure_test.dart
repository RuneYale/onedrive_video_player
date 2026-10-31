import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/errors/app_failure.dart';

DioException _dio({
  int? status,
  Object? data,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/items');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: status,
            data: data,
          ),
  );
}

void main() {
  group('AppFailure.from', () {
    test('returns an existing failure unchanged', () {
      const failure = NotFoundFailure();
      expect(AppFailure.from(failure), same(failure));
    });

    test('connection failures become NetworkFailure', () {
      expect(
        AppFailure.from(_dio(type: DioExceptionType.connectionError)),
        isA<NetworkFailure>(),
      );
      expect(
        AppFailure.from(_dio(type: DioExceptionType.connectionTimeout)),
        isA<NetworkFailure>(),
      );
    });

    test('401 and 403 become AuthFailure', () {
      expect(AppFailure.from(_dio(status: 401)), isA<AuthFailure>());
      expect(AppFailure.from(_dio(status: 403)), isA<AuthFailure>());
    });

    test('404 becomes NotFoundFailure and 429 RateLimitFailure', () {
      expect(AppFailure.from(_dio(status: 404)), isA<NotFoundFailure>());
      expect(AppFailure.from(_dio(status: 429)), isA<RateLimitFailure>());
    });

    test('5xx becomes ServerFailure and keeps the Graph message as detail', () {
      final failure = AppFailure.from(
        _dio(
          status: 500,
          data: {
            'error': {'code': 'generalException', 'message': 'boom'},
          },
        ),
      );
      expect(failure, isA<ServerFailure>());
      expect(failure.detail, 'boom');
    });

    test('non-HTTP errors stay generic instead of leaking their text', () {
      final failure = AppFailure.from(StateError('Bad state: no element'));
      expect(failure, isA<UnknownFailure>());
      expect(failure.message, isNot(contains('Bad state')));
      expect(failure.detail, contains('Bad state'));
    });

    test('the cancelled case has a calm message', () {
      final failure = AppFailure.from(_dio(type: DioExceptionType.cancel));
      expect(failure.message, 'The request was cancelled.');
    });
  });
}
