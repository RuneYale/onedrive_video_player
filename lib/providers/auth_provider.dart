import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/auth_tokens.dart';
import '../core/services/auth_service.dart';
import '../core/services/token_storage.dart';

/// Shared [Dio] instance for identity + Graph HTTP calls.
final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
});

final tokenStorageProvider =
    Provider<TokenStorage>((ref) => const TokenStorage());

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(dioProvider), ref.watch(tokenStorageProvider));
});

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthRestoring extends AuthState {
  const AuthRestoring();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Sign-in in progress; [deviceCode] holds the code the user must enter.
class AuthAuthenticating extends AuthState {
  const AuthAuthenticating(this.deviceCode);
  final DeviceCodeResponse deviceCode;
}

class Authenticated extends AuthState {
  const Authenticated({required this.tokens, this.displayName, this.email});
  final AuthTokens tokens;
  final String? displayName;
  final String? email;
}

class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}

class AuthNotifier extends Notifier<AuthState> {
  late final AuthService _auth;
  late final TokenStorage _storage;
  int _pollGen = 0;

  @override
  AuthState build() {
    _auth = ref.read(authServiceProvider);
    _storage = ref.read(tokenStorageProvider);
    _pollGen = 0;
    unawaited(_restore());
    // Increment the poll generation on dispose to cancel any in-flight poll.
    ref.onDispose(() => _pollGen++);
    return const AuthRestoring();
  }

  Future<void> _restore() async {
    try {
      await _auth.restore();
      if (!ref.mounted) return;
      if (_auth.current != null) {
        final name = await _storage.userName();
        final email = await _storage.userEmail();
        if (!ref.mounted) return;
        state = Authenticated(
          tokens: _auth.current!,
          displayName: name,
          email: email,
        );
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      // Any failure during restore (storage, refresh, profile lookup) must
      // not leave the app stuck on a blank screen — fall back to signed out.
      if (ref.mounted) state = const AuthUnauthenticated();
    }
  }

  /// Starts the device-code sign-in flow and begins polling.
  Future<void> signIn() async {
    try {
      final dc = await _auth.requestDeviceCode();
      _pollGen++;
      state = AuthAuthenticating(dc);
      unawaited(_poll(dc, gen: _pollGen, intervalSeconds: dc.interval));
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> _poll(
    DeviceCodeResponse dc, {
    required int gen,
    required int intervalSeconds,
  }) async {
    if (gen != _pollGen) return;
    try {
      final result = await _auth.pollForToken(dc.deviceCode);
      if (gen != _pollGen) return;
      state = Authenticated(
        tokens: result.tokens,
        displayName: result.displayName,
        email: result.email,
      );
    } on DeviceCodePendingException {
      await Future<void>.delayed(Duration(seconds: intervalSeconds));
      if (gen == _pollGen && state is AuthAuthenticating) {
        unawaited(_poll(dc, gen: gen, intervalSeconds: intervalSeconds));
      }
    } on DeviceCodeSlowDownException {
      final slower = intervalSeconds + 5;
      await Future<void>.delayed(Duration(seconds: slower));
      if (gen == _pollGen && state is AuthAuthenticating) {
        unawaited(_poll(dc, gen: gen, intervalSeconds: slower));
      }
    } on DeviceCodeExpiredException catch (e) {
      if (gen == _pollGen) state = AuthError('Device code expired: ${e.message}');
    } on DeviceCodeDeniedException {
      if (gen == _pollGen) state = const AuthError('Sign-in was denied.');
    } on AuthException catch (e) {
      if (gen == _pollGen) state = AuthError(e.message);
    } catch (e) {
      if (gen == _pollGen) state = AuthError(e.toString());
    }
  }

  /// Cancels an in-progress sign-in.
  void cancelSignIn() {
    _pollGen++;
    state = const AuthUnauthenticated();
  }

  Future<void> signOut() async {
    _pollGen++;
    await _auth.signOut();
    state = const AuthUnauthenticated();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);