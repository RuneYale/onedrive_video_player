import 'package:onedrive_video_player/core/services/secret_store.dart';

/// In-memory [SecretStore] so token persistence can be tested without the
/// platform channels behind Keystore / DPAPI.
class FakeSecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
