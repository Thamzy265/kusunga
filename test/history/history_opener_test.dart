import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

void main() {
  late Directory dir;
  late FakeKeyStore keys;
  late FakeLog log;

  final stores = <HistoryStore>[];

  Future<OpenedHistory> open({
    bool Function(dynamic)? cipherActive,
    int seed = 1,
  }) async {
    final opened = await openHistory(
      keys: keys,
      directory: dir.path,
      log: log,
      random: Random(seed),
      today: () => DateTime(2026, 11, 3),
      cipherActive: cipherActive,
    );
    stores.add(opened.store);
    return opened;
  }

  List<String> files() =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_open_');
    keys = FakeKeyStore();
    log = FakeLog();
  });
  tearDown(() {
    // Windows cannot delete an open file: close every store first.
    for (final s in stores) {
      s.close();
    }
    stores.clear();
    dir.deleteSync(recursive: true);
  });

  test('first run makes a 256-bit key, stores it and opens the file', () async {
    final opened = await open();

    expect(opened.store, isA<SqliteHistoryStore>());
    expect(opened.notices, isEmpty);
    expect(keys.stored, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(files(), ['kusunga.db']);
    opened.store.close();
  });

  test('second run reads the same key and finds the history', () async {
    final first = await open();
    first.store.insertOrBump('kept', ClipKind.text, 1);
    first.store.close();
    final key = keys.stored;

    final second = await open();
    expect(second.store.list().single.preview, 'kept');
    expect(keys.stored, key);
    expect(keys.writes, 1, reason: 'the key is made once');
    second.store.close();
  });

  for (final reason in ['read fails', 'write fails', 'read-back differs']) {
    test('keychain $reason: memory only, nothing written to disk', () async {
      switch (reason) {
        case 'read fails':
          keys.readError = Exception('-34018');
        case 'write fails':
          keys.writeError = Exception('denied');
        default:
          keys.readBackOverride = 'a' * 64;
      }

      final opened = await open();

      expect(opened.store, isA<MemoryHistoryStore>());
      expect(opened.notices, {HistoryNotice.memoryOnly});
      opened.store.insertOrBump('secret text', ClipKind.text, 1);
      expect(opened.store.count, 1);
      expect(files(), isEmpty, reason: 'never an unencrypted file');
      expect(log.codes, isNotEmpty);
    });
  }

  test(
    'a keychain error number is logged, nothing else from the error',
    () async {
      keys.readError = PlatformException(
        code: 'Unexpected security result code',
        message: "Code: -34018, Message: A required entitlement isn't present.",
      );
      await open();
      expect(log.codes, [LogCode.keychainReadFailed]);
      expect(log.details, [-34018]);
    },
  );

  test('a wrong key: old file moved aside, new history, one notice', () async {
    final first = await open();
    first.store.insertOrBump('old', ClipKind.text, 1);
    first.store.close();
    final oldBytes = File('${dir.path}/kusunga.db').readAsBytesSync();
    keys.stored = 'b' * 64;

    final opened = await open();

    expect(opened.store, isA<SqliteHistoryStore>());
    expect(opened.store.count, 0);
    expect(opened.notices, {HistoryNotice.readError});
    expect(files(), ['kusunga.db', 'kusunga.db.unreadable-2026-11-03']);
    expect(
      File('${dir.path}/kusunga.db.unreadable-2026-11-03').readAsBytesSync(),
      oldBytes,
      reason: 'the old file is kept, not deleted',
    );
    expect(log.codes, contains(LogCode.storeUnreadable));
    opened.store.close();
  });

  test('a corrupt file is moved aside too', () async {
    File('${dir.path}/kusunga.db').writeAsBytesSync(List.filled(5000, 9));
    final opened = await open();
    expect(opened.notices, {HistoryNotice.readError});
    expect(opened.store.count, 0);
    opened.store.close();
  });

  test(
    'a lost keychain item with an old file: new key, old file aside',
    () async {
      final first = await open();
      first.store.insertOrBump('old', ClipKind.text, 1);
      first.store.close();
      keys.stored = null; // item deleted

      final opened = await open(seed: 2);

      expect(opened.notices, {HistoryNotice.readError});
      expect(opened.store.count, 0);
      expect(keys.stored, isNotNull);
      opened.store.close();
    },
  );

  test(
    'two unreadable files on the same day do not overwrite each other',
    () async {
      File(
        '${dir.path}/kusunga.db.unreadable-2026-11-03',
      ).writeAsStringSync('x');
      File('${dir.path}/kusunga.db').writeAsBytesSync(List.filled(5000, 9));
      final opened = await open();
      expect(files().where((f) => f.contains('unreadable')).length, 2);
      opened.store.close();
    },
  );

  test('no cipher in this build: memory only, nothing written', () async {
    final opened = await open(cipherActive: (_) => false);
    expect(opened.store, isA<MemoryHistoryStore>());
    expect(opened.notices, {HistoryNotice.memoryOnly});
    expect(files(), isEmpty);
    expect(log.codes, contains(LogCode.encryptionUnavailable));
  });

  test('a data folder that cannot be used: memory only', () async {
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    final opened = await openHistory(
      keys: keys,
      directory: '${blocker.path}/inner',
      log: log,
      random: Random(1),
      today: () => DateTime(2026, 11, 3),
    );
    expect(opened.store, isA<MemoryHistoryStore>());
    expect(opened.notices, {HistoryNotice.memoryOnly});
  });

  for (final which in ['read', 'write', 'read-back']) {
    test('a keychain $which that never answers (unanswered prompt): memory '
        'only, no file, keychainTimeout logged', () async {
      switch (which) {
        case 'read':
          keys.hang = true;
        case 'write':
          keys.hangWrite = true;
        default:
          keys.hangReadBack = true;
      }
      final opened = await openHistory(
        keys: keys,
        directory: dir.path,
        log: log,
        keyTimeout: const Duration(milliseconds: 50),
      );
      stores.add(opened.store);

      expect(opened.store, isA<MemoryHistoryStore>());
      expect(opened.notices, {HistoryNotice.memoryOnly});
      expect(files(), isEmpty, reason: 'nothing written to disk');
      expect(log.codes, [LogCode.keychainTimeout]);
      if (which == 'read') {
        expect(keys.writes, 0, reason: 'no key is made when the read hangs');
        expect(keys.stored, isNull);
      }
    });
  }
}
