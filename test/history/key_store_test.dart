import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reads nothing before a key exists, then the key that was written',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureKeyStore();
      expect(await store.read(), isNull);

      await store.write('ab' * 32);
      expect(await store.read(), 'ab' * 32);
    },
  );

  test('uses the login keychain so unsigned builds can reach it', () {
    expect(SecureKeyStore.macOptions.usesDataProtectionKeychain, isFalse);
    expect(SecureKeyStore.macOptions.accountName, 'com.wnasoni.kusunga');
  });

  test(
    'delete removes the key, and is fine when there is none (M1.8)',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureKeyStore();
      await store.write('ab' * 32);
      await store.delete();
      expect(await store.read(), isNull);
      await store.delete();
      expect(await store.read(), isNull);
    },
  );
}
