import 'package:flutter/services.dart';

import 'secret_store.dart';

/// Android implementation: AES-GCM with a key held by the Android Keystore.
///
/// The ciphertext lives in a private preferences file; the key never leaves
/// the Keystore (hardware-backed on most devices), so a copied file cannot be
/// decrypted on another device. Implemented in `MainActivity.kt`
/// (`odplayer/secure` channel) because Keystore access needs the platform.
class AndroidKeystoreSecretStore implements SecretStore {
  const AndroidKeystoreSecretStore();

  static const _channel = MethodChannel('odplayer/secure');

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', <String, Object?>{'key': key});

  @override
  Future<void> write(String key, String value) => _channel.invokeMethod<void>(
    'write',
    <String, Object?>{'key': key, 'value': value},
  );

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', <String, Object?>{'key': key});
}
