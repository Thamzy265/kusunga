import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'key_store.dart';

/// Where [WindowsKeyStore] keeps the key. A seam so tests need no Windows.
abstract interface class CredentialVault {
  /// The secret stored under [target], or null if there is none. Throws on any
  /// other failure.
  String? read(String target);
  void write(String target, String value);
}

/// The database key in Windows Credential Manager (ADR 0002): a generic
/// credential, saved for this user on this machine only (it does not roam).
class WindowsKeyStore implements KeyStore {
  WindowsKeyStore(this._vault);

  static const targetName = 'com.wnasoni.kusunga/history_db_key';
  final CredentialVault _vault;

  @override
  Future<String?> read() async => _vault.read(targetName);

  @override
  Future<void> write(String keyHex) async => _vault.write(targetName, keyHex);
}

/// Credential Manager through CredReadW / CredWriteW.
class Win32CredentialVault implements CredentialVault {
  @override
  String? read(String target) => using((arena) {
    final out = arena<Pointer<CREDENTIAL>>();
    final result = CredRead(arena.pcwstr(target), CRED_TYPE_GENERIC, out);
    if (!result.value) {
      if (result.error == ERROR_NOT_FOUND) return null;
      throw WindowsException(result.error.toHRESULT());
    }
    try {
      final cred = out.value.ref;
      return utf8.decode(
        cred.CredentialBlob.asTypedList(cred.CredentialBlobSize),
      );
    } finally {
      CredFree(out.value);
    }
  });

  @override
  void write(String target, String value) => using((arena) {
    final bytes = utf8.encode(value);
    final credential = arena<CREDENTIAL>();
    credential.ref
      ..Type = CRED_TYPE_GENERIC
      ..TargetName = arena.pwstr(target)
      ..UserName = arena.pwstr('Kusunga')
      // LOCAL_MACHINE: kept for this user on this machine, never roamed.
      ..Persist = CRED_PERSIST_LOCAL_MACHINE
      ..CredentialBlob = bytes.toNative(allocator: arena)
      ..CredentialBlobSize = bytes.length;
    final result = CredWrite(credential, 0);
    if (!result.value) throw WindowsException(result.error.toHRESULT());
  });
}

/// Windows: Credential Manager. Mac: the keychain package.
KeyStore keyStoreFor({required bool isWindows, CredentialVault? vault}) =>
    isWindows
    ? WindowsKeyStore(vault ?? Win32CredentialVault())
    : SecureKeyStore();
