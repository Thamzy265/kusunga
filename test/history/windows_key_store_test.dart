import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/key_store.dart';
import 'package:kusunga/history/windows_key_store.dart';

class FakeVault implements CredentialVault {
  final entries = <String, String>{};
  Object? error;
  final calls = <String>[];

  @override
  String? read(String target) {
    calls.add('read $target');
    if (error != null) throw error!;
    return entries[target];
  }

  @override
  void delete(String target) {
    calls.add('delete $target');
    entries.remove(target);
  }

  @override
  void write(String target, String value) {
    calls.add('write $target');
    if (error != null) throw error!;
    entries[target] = value;
  }
}

void main() {
  test(
    'the key lives in a generic credential named com.wnasoni.kusunga/history_db_key',
    () async {
      final vault = FakeVault();
      final store = WindowsKeyStore(vault);
      expect(WindowsKeyStore.targetName, 'com.wnasoni.kusunga/history_db_key');

      expect(await store.read(), isNull, reason: 'no credential yet');
      await store.write('ab' * 32);
      expect(await store.read(), 'ab' * 32);
      expect(vault.entries.keys.single, 'com.wnasoni.kusunga/history_db_key');
    },
  );

  test(
    'a vault failure reaches the caller (so history runs memory only)',
    () async {
      final vault = FakeVault()..error = StateError('access denied');
      final store = WindowsKeyStore(vault);
      expect(store.read(), throwsStateError);
      expect(store.write('ab' * 32), throwsStateError);
    },
  );

  test(
    'Windows uses Credential Manager, other systems the keychain package',
    () {
      expect(
        keyStoreFor(isWindows: true, vault: FakeVault()),
        isA<WindowsKeyStore>(),
      );
      expect(
        keyStoreFor(isWindows: false, vault: FakeVault()),
        isA<SecureKeyStore>(),
      );
    },
  );
}
