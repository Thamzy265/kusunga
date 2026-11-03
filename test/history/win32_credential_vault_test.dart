@TestOn('windows')
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/history/windows_key_store.dart';
import 'package:kusunga/log/app_log.dart';

/// Runs the real Credential Manager. Only on Windows (the CI Windows job);
/// skipped elsewhere. Uses throwaway credentials and removes them.
void main() {
  final vault = Win32CredentialVault();
  late String target;

  setUp(() {
    target = 'com.wnasoni.kusunga.test/${Random.secure().nextInt(1 << 32)}';
  });
  tearDown(() => vault.delete(target));

  test('a credential that is not there reads as null', () {
    expect(vault.read(target), isNull);
  });

  test('write then read gives the same value; overwrite works', () {
    vault.write(target, 'ab' * 32);
    expect(vault.read(target), 'ab' * 32);
    vault.write(target, 'cd' * 32);
    expect(vault.read(target), 'cd' * 32);
  });

  test('delete removes it, and deleting again is fine', () {
    vault.write(target, 'ab' * 32);
    vault.delete(target);
    expect(vault.read(target), isNull);
    vault.delete(target);
  });

  test(
    'openHistory with the Windows key store opens an encrypted store',
    () async {
      final dir = Directory.systemTemp.createTempSync('kusunga_win_');
      final keys = WindowsKeyStore(vault, target: target);
      final opened = await openHistory(
        keys: keys,
        directory: dir.path,
        log: const NullErrorLog(),
      );
      addTearDown(() {
        opened.store.close();
        dir.deleteSync(recursive: true);
      });
      expect(opened.store, isA<SqliteHistoryStore>());
      expect(opened.notices, isEmpty);
      expect(vault.read(target), matches(RegExp(r'^[0-9a-f]{64}\$')));
    },
  );
}
