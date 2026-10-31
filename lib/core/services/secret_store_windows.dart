import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';

/// Windows implementation: DPAPI.
///
/// `CryptProtectData` encrypts each value with a key derived from the
/// signed-in Windows user, and the ciphertext is kept in the preferences file.
/// The file on disk is therefore never plaintext, and copying it to another
/// account or machine does not reveal the tokens.
///
/// No plugin is used on purpose: the common secure-storage plugin needs the
/// Visual C++ ATL headers, which are not part of every Visual Studio install.
class WindowsDpapiSecretStore implements SecretStore {
  const WindowsDpapiSecretStore();

  static const _keyPrefix = 'odvp_secret_';
  static const int _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN

  static final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _cryptProtectData = _crypt32.lookupFunction<
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    ),
    int Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    )
  >('CryptProtectData');

  static final _cryptUnprotectData = _crypt32.lookupFunction<
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    ),
    int Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    )
  >('CryptUnprotectData');

  static final _localFree = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)
  >('LocalFree');

  static final _getLastError = _kernel32.lookupFunction<
    Uint32 Function(),
    int Function()
  >('GetLastError');

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('$_keyPrefix$key');
    if (stored == null || stored.isEmpty) return null;
    try {
      return utf8.decode(_crypt(base64Decode(stored), decrypt: true));
    } catch (_) {
      // Corrupt, or protected for a different Windows user: treat as missing
      // so the app returns to the sign-in screen instead of crashing.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = base64Encode(_crypt(utf8.encode(value), decrypt: false));
    await prefs.setString('$_keyPrefix$key', encrypted);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$key');
  }

  Uint8List _crypt(List<int> input, {required bool decrypt}) {
    final inBytes = calloc<Uint8>(input.length);
    final inBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    try {
      inBytes.asTypedList(input.length).setAll(0, input);
      inBlob.ref
        ..cbData = input.length
        ..pbData = inBytes;

      final call = decrypt ? _cryptUnprotectData : _cryptProtectData;
      final ok = call(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _uiForbidden,
        outBlob,
      );
      if (ok == 0) {
        throw StateError(
          '${decrypt ? 'CryptUnprotectData' : 'CryptProtectData'} failed '
          '(win32 ${_getLastError()})',
        );
      }
      final out = outBlob.ref;
      return Uint8List.fromList(out.pbData.asTypedList(out.cbData));
    } finally {
      final produced = outBlob.ref.pbData;
      if (produced != nullptr) _localFree(produced.cast());
      calloc.free(inBlob);
      calloc.free(outBlob);
      calloc.free(inBytes);
    }
  }
}

/// Win32 `DATA_BLOB`.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}
