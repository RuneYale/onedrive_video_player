import 'package:dio/dio.dart';

/// A failure the UI can actually show.
///
/// Every service throws (or maps to) one of these instead of leaking
/// `DioException` / `StateError` text into a screen. [message] is the one-line
/// sentence a screen shows; [detail] keeps the technical cause for logs and for
/// a secondary, smaller line.
///
/// Not sealed on purpose: `AuthException` (in the auth service) extends this
/// class so sign-in errors share the same display path.
abstract class AppFailure implements Exception {
  const AppFailure(this.message, {this.detail});

  /// Short, human, actionable sentence (no stack traces, no HTTP jargon).
  final String message;

  /// Technical cause. Never the primary text.
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';

  /// Maps anything a service or the player can throw to a displayable failure.
  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (error is DioException) return _fromDio(error);
    return UnknownFailure(detail: error.toString());
  }

  static AppFailure _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure(
          message: 'The connection timed out. Check your network and try again.',
        );
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badCertificate:
        return const NetworkFailure(
          message: 'The secure connection to Microsoft could not be verified.',
        );
      case DioExceptionType.cancel:
        return const UnknownFailure(message: 'The request was cancelled.');
      case DioExceptionType.badResponse:
        break;
      case DioExceptionType.unknown:
        final inner = e.error;
        if (inner is AppFailure) return inner;
        return UnknownFailure(detail: e.message ?? inner?.toString());
    }

    final status = e.response?.statusCode;
    final serverMessage = _graphMessage(e.response?.data);
    if (status == 401) {
      return AuthFailure(
        message: 'Your sign-in has expired.',
        detail: serverMessage ?? 'HTTP 401',
      );
    }
    if (status == 403) {
      return const AuthFailure(
        message: 'You do not have permission to open this item.',
      );
    }
    if (status == 404) {
      return const NotFoundFailure();
    }
    if (status == 429) {
      return const RateLimitFailure();
    }
    if (status != null && status >= 500) {
      return ServerFailure(detail: serverMessage ?? 'HTTP $status');
    }
    return UnknownFailure(detail: serverMessage ?? 'HTTP $status');
  }

  /// Microsoft Graph errors look like `{"error":{"code","message"}}`; the
  /// identity endpoints use a flat `{"error","error_description"}`.
  static String? _graphMessage(Object? data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (error is String && error.isNotEmpty) {
      final description = data['error_description'];
      if (description is String && description.isNotEmpty) return description;
      return error;
    }
    return null;
  }
}

/// Offline, DNS failure, timeout, TLS problem.
final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    String message =
        'You appear to be offline. Check your connection and try again.',
    String? detail,
  }) : super(message, detail: detail);
}

/// The session is gone or the account may not do this.
final class AuthFailure extends AppFailure {
  const AuthFailure({
    String message = 'Your sign-in has expired.',
    String? detail,
  }) : super(message, detail: detail);
}

/// No session at all — the caller should send the user back to sign-in.
final class NotAuthenticatedFailure extends AppFailure {
  const NotAuthenticatedFailure() : super('Please sign in to continue.');
}

/// The item was deleted, moved, or never belonged to this account.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure()
    : super('This item is no longer in your OneDrive.');
}

/// Graph throttling: retrying after a moment usually works.
final class RateLimitFailure extends AppFailure {
  const RateLimitFailure()
    : super('OneDrive is busy right now. Please try again in a moment.');
}

/// 5xx from Microsoft.
final class ServerFailure extends AppFailure {
  const ServerFailure({
    String message = 'OneDrive could not be reached. Please try again.',
    String? detail,
  }) : super(message, detail: detail);
}

/// Playback / subtitle failures (mpv errors, expired stream URLs).
final class PlaybackFailure extends AppFailure {
  const PlaybackFailure({
    String message =
        'Playback stopped. The stream may have expired — try again.',
    String? detail,
  }) : super(message, detail: detail);
}

/// Anything unmapped. The message stays generic on purpose.
final class UnknownFailure extends AppFailure {
  const UnknownFailure({
    String message = 'Something went wrong. Please try again.',
    String? detail,
  }) : super(message, detail: detail);
}
