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
}
