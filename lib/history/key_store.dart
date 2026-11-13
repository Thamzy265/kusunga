import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the database key lives: the Mac Keychain or Windows Credential
/// Manager. The key is never written anywhere else.
abstract interface class KeyStore {
  /// The key as 64 hex characters, or null if there is none yet. Throws if
  /// the keychain cannot be reached.
  Future<String?> read();
  Future<void> write(String keyHex);

  /// Removes the key (Delete everything, M1.8). No error if there is none;
  /// throws if the keychain refuses, and then the key is still there.
  Future<void> delete();
}

class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(mOptions: macOptions);

  /// The Mac data-protection keychain needs a signed app with a keychain
  /// entitlement: an unsigned or ad-hoc build gets errSecMissingEntitlement
  /// (-34018) and the history would be memory only. The login keychain does
  /// not, so it is used. An update signed with a different identity may make
  /// macOS ask the user once for keychain access. Revisit with the signed
  /// builds in M1.9 (PM decision on code signing, D5).
  static const macOptions = MacOsOptions(
    usesDataProtectionKeychain: false,
    accountName: 'com.wnasoni.kusunga',
  );

  static const entryName = 'history_db_key';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: entryName);

  @override
  Future<void> write(String keyHex) =>
      _storage.write(key: entryName, value: keyHex);

  @override
  Future<void> delete() => _storage.delete(key: entryName);
}
