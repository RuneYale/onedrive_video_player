import 'package:flutter/foundation.dart';

import 'secret_store_android.dart';
import 'secret_store_windows.dart';

/// Minimal key/value secret store.
///
/// Abstracted so token persistence can be exercised in unit tests without
/// platform channels or native crypto.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Default store for the current platform.
///
/// - Android: AES-GCM key in the Android Keystore (see MainActivity).
/// - Windows: DPAPI (`CryptProtectData`), ciphertext in preferences.
/// - Anything else: session-only, so secrets are never written in the clear.
SecretStore defaultSecretStore() => _instance ??= _create();

SecretStore? _instance;

SecretStore _create() => switch (defaultTargetPlatform) {
  TargetPlatform.android => const AndroidKeystoreSecretStore(),
  TargetPlatform.windows => const WindowsDpapiSecretStore(),
  _ => InMemorySecretStore(),
};

/// Dispatches to [defaultSecretStore] lazily; const so [TokenStorage] keeps a
/// const constructor.
class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  @override
  Future<String?> read(String key) => defaultSecretStore().read(key);

  @override
  Future<void> write(String key, String value) =>
      defaultSecretStore().write(key, value);

  @override
  Future<void> delete(String key) => defaultSecretStore().delete(key);
}

/// Keeps values in memory only — used on platforms this app doesn't ship, and
/// as a test double.
class InMemorySecretStore implements SecretStore {
  InMemorySecretStore();

  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
