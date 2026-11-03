import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the database key lives: the Mac Keychain or Windows Credential
/// Manager. The key is never written anywhere else.
abstract interface class KeyStore {
  /// The key as 64 hex characters, or null if there is none yet. Throws if
  /// the keychain cannot be reached.
  Future<String?> read();
  Future<void> write(String keyHex);
}

class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(
              accountName: 'uk.org.cgatechnologies.kusunga',
            ),
          );

  static const entryName = 'history_db_key';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: entryName);

  @override
  Future<void> write(String keyHex) =>
      _storage.write(key: entryName, value: keyHex);
}

@visibleForTesting
const keyEntryName = SecureKeyStore.entryName;
