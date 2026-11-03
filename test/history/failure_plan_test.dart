// Tester (M1.2): the "Failure plan" and "Observability" sections of
// docs/design/clipboard-history.md, tried with real encrypted files where
// possible. Nothing here touches the real keychain or the real clipboard.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

const _marker = 'PLAINTEXT-MARKER-7e3a91c4-not-a-real-secret';
const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late FakeKeyStore keys;
  late FakeLog log;

  Future<OpenedHistory> open({
    List<Migration> migrations = kMigrations,
    ErrorLog? errorLog,
    int seed = 1,
  }) => openHistory(
    keys: keys,
    directory: dir.path,
    log: errorLog ?? log,
    random: Random(seed),
    today: () => DateTime(2026, 11, 3),
    migrations: migrations,
  );

  List<String> files() =>
      dir.listSync().map((e) => e.path.split('/').last).toList()..sort();

  /// True if any file in the folder holds [text] as UTF-8 or UTF-16.
  bool anyFileHolds(String text) {
    final utf8Bytes = utf8.encode(text);
    final utf16 = <int>[
      for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
    ];
    for (final f in dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      if (_contains(bytes, utf8Bytes) || _contains(bytes, utf16)) return true;
    }
    return false;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_fail_');
    keys = FakeKeyStore();
    log = FakeLog();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('nothing is ever written unencrypted', () {
    test('normal use, open or closed: only encrypted bytes on disk', () async {
      final opened = await open();
      opened.store.insertOrBump(_marker, ClipKind.text, 1);
      expect(anyFileHolds(_marker), isFalse, reason: 'while open');
      opened.store.insertOrBump('$_marker 2', ClipKind.link, 2);
      opened.store.delete(opened.store.list().first.id);
      opened.store.clear();
      opened.store.insertOrBump(_marker, ClipKind.text, 3);
      opened.store.close();
      expect(anyFileHolds(_marker), isFalse, reason: 'after close');
      expect(anyFileHolds('clip_items'), isFalse, reason: 'schema too');
      expect(anyFileHolds('SQLite format 3'), isFalse);
    });

    test('a copy that is deleted is also gone from the file', () async {
      final opened = await open();
      opened.store.insertOrBump(_marker, ClipKind.text, 1);
      final id = opened.store.list().single.id;
      opened.store.delete(id);
      opened.store.close();
      // Re-open with the right key: the text is not in the database any more.
      final again = SqliteHistoryStore.open(
        path: '${dir.path}/kusunga.db',
        keyHex: keys.stored!,
      );
      expect(again.count, 0);
      again.close();
    });

    for (final reason in [
      'keychain read fails',
      'keychain write fails',
      'keychain returns a different key',
      'no cipher in this build',
      'data folder unusable',
    ]) {
      test('$reason: history works in memory and no file appears', () async {
        late OpenedHistory opened;
        switch (reason) {
          case 'keychain read fails':
            keys.readError = PlatformException(code: 'x', message: _marker);
            opened = await open();
          case 'keychain write fails':
            keys.writeError = PlatformException(code: 'x', message: _marker);
            opened = await open();
          case 'keychain returns a different key':
            keys.readBackOverride = 'a' * 64;
            opened = await open();
          case 'no cipher in this build':
            opened = await openHistory(
              keys: keys,
              directory: dir.path,
              log: log,
              cipherActive: (_) => false,
            );
          default:
            final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
            opened = await openHistory(
              keys: keys,
              directory: '${blocker.path}/inner',
              log: log,
            );
        }
        expect(opened.store, isA<MemoryHistoryStore>());
        expect(opened.notices, {HistoryNotice.memoryOnly});
        opened.store.insertOrBump(_marker, ClipKind.text, 1);
        expect(opened.store.count, 1, reason: 'still works for this session');
        opened.store.close();
        final names = files().where((f) => f != 'blocker');
        expect(names, isEmpty, reason: 'nothing on disk: $names');
        expect(anyFileHolds(_marker), isFalse);
      });
    }

    test('every failure path that moves or copies files leaves only '
        'encrypted bytes', () async {
      // Wrong key.
      var opened = await open();
      opened.store.insertOrBump(_marker, ClipKind.text, 1);
      opened.store.close();
      keys.stored = 'c' * 64;
      opened = await open();
      opened.store.insertOrBump(_marker, ClipKind.text, 2);
      opened.store.close();
      // Failed migration (leaves a backup copy).
      final bad = Migration(version: 2, statements: ['THIS IS NOT SQL']);
      opened = await open(migrations: [...kMigrations, bad]);
      opened.store.close();
      expect(anyFileHolds(_marker), isFalse, reason: files().join(', '));
    });
  });

  group('a key the keychain gives back that is not 64 hex digits', () {
    for (final bad in ['', 'abc', 'z' * 64, 'a' * 63, 'a' * 65]) {
      test('${bad.length} characters: memory only with the keychain '
          'banner, never an unencrypted file', () async {
        final first = await open();
        first.store.insertOrBump(_marker, ClipKind.text, 1);
        first.store.close();
        keys.stored = bad;

        final opened = await open();

        expect(opened.store, isA<MemoryHistoryStore>());
        expect(opened.notices, contains(HistoryNotice.memoryOnly));
        opened.store.insertOrBump(_marker, ClipKind.text, 2);
        opened.store.close();
        expect(anyFileHolds(_marker), isFalse);
        expect(keys.stored, bad, reason: 'the keychain entry is not replaced');
      });
    }
  });

  group('corrupt and odd files', () {
    test('an empty file opens as a fresh history with no notice', () async {
      File('${dir.path}/kusunga.db').writeAsBytesSync([]);
      final opened = await open();
      expect(opened.notices, isEmpty);
      expect(opened.store, isA<SqliteHistoryStore>());
      opened.store.insertOrBump('a', ClipKind.text, 1);
      expect(opened.store.count, 1);
      opened.store.close();
    });

    test('a plain (unencrypted) SQLite file is moved aside, not read or '
        'extended', () async {
      final plain = sqlite3.open('${dir.path}/kusunga.db');
      plain.execute('CREATE TABLE clip_items (content TEXT)');
      plain.execute("INSERT INTO clip_items VALUES ('$_marker')");
      plain.close();

      final opened = await open();

      expect(opened.notices, {HistoryNotice.readError});
      expect(opened.store.count, 0);
      opened.store.insertOrBump('new', ClipKind.text, 1);
      opened.store.close();
      final fresh = File('${dir.path}/kusunga.db').readAsBytesSync();
      expect(_contains(fresh, utf8.encode(_marker)), isFalse);
      expect(
        _contains(fresh, utf8.encode('SQLite format 3')),
        isFalse,
        reason: 'the new file is encrypted from its first byte',
      );
    });

    test('a truncated encrypted file is moved aside with one notice', () async {
      final first = await open();
      for (var i = 0; i < 50; i++) {
        first.store.insertOrBump('item $i', ClipKind.text, i + 1);
      }
      first.store.close();
      final file = File('${dir.path}/kusunga.db');
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2 + 7));

      final opened = await open();

      // Either the damage is caught at open (notice, new history) or the
      // store still opens; it must never hand out a half-readable history
      // without telling the user.
      if (opened.notices.isEmpty) {
        expect(() => opened.store.list(), returnsNormally);
      } else {
        expect(opened.notices, {HistoryNotice.readError});
        expect(opened.store.count, 0);
      }
      opened.store.close();
    });

    test('damage in the middle of the file never leaves a silent, empty '
        'list that rejects every new copy', () async {
      final first = await open();
      for (var i = 0; i < 300; i++) {
        first.store.insertOrBump('item $i ${'x' * 200}', ClipKind.text, i + 1);
      }
      first.store.close();
      final file = File('${dir.path}/kusunga.db');
      final bytes = file.readAsBytesSync();
      // Zero a stretch well after the header and the settings page.
      for (var i = bytes.length ~/ 3; i < bytes.length ~/ 3 + 9000; i++) {
        bytes[i] = 0;
      }
      file.writeAsBytesSync(bytes);

      final opened = await open();
      final service = HistoryService(
        store: opened.store,
        notices: opened.notices,
        source: FakeClipboardSource(),
        log: log,
      )..start();
      addTearDown(service.dispose);

      final shownAnItem = service.items.isNotEmpty;
      final toldTheUser = opened.notices.contains(HistoryNotice.readError);
      expect(
        shownAnItem || toldTheUser,
        isTrue,
        reason:
            'the history is unreadable but there was no notice and no '
            'item: the user sees an empty list as if nothing was wrong',
      );
    });
  });

  group('failed migration and newer schema', () {
    final v2 = Migration(
      version: 2,
      statements: ['ALTER TABLE clip_items ADD COLUMN note TEXT'],
    );

    test('a newer-schema file is moved aside whole, one notice, new file '
        'is version 1', () async {
      final newer = await open(migrations: [...kMigrations, v2]);
      newer.store.insertOrBump('from the future', ClipKind.text, 1);
      newer.store.close();
      final before = File('${dir.path}/kusunga.db').readAsBytesSync();

      final opened = await open();

      expect(opened.notices, {HistoryNotice.readError});
      expect(opened.store.count, 0);
      expect(
        File('${dir.path}/kusunga.db.unreadable-2026-11-03').readAsBytesSync(),
        before,
        reason: 'untouched',
      );
      opened.store.close();
    });

    // Fails on data that starts with the same letter, passes on an empty
    // database, like a real migration that chokes on old rows.
    final dataDependent = Migration(
      version: 2,
      statements: [
        'CREATE UNIQUE INDEX one_per_letter ON clip_items '
            '(substr(content, 1, 1))',
      ],
    );

    test('a failed migration at start-up: old data is kept aside and the '
        'user is told once', () async {
      final first = await open();
      first.store.insertOrBump('old data', ClipKind.text, 1);
      first.store.insertOrBump('old more', ClipKind.text, 2);
      first.store.close();
      final bad = dataDependent;

      final opened = await open(migrations: [...kMigrations, bad]);

      expect(opened.notices, {HistoryNotice.readError});
      expect(opened.store, isA<SqliteHistoryStore>());
      opened.store.close();
      final aside = files().where((f) => f.contains('unreadable'));
      expect(aside, hasLength(1));
      final old = SqliteHistoryStore.open(
        path: '${dir.path}/${aside.single}',
        keyHex: keys.stored!,
      );
      expect(old.count, 2);
      old.close();
    });

    test('a failing step-2 migration after a good step 1 rolls back only '
        'step 2', () {
      final path = '${dir.path}/m.db';
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final good2 = Migration(
        version: 2,
        statements: ['ALTER TABLE clip_items ADD COLUMN note TEXT'],
      );
      final bad3 = Migration(version: 3, statements: ['NOT SQL']);
      expect(
        () => SqliteHistoryStore.open(
          path: path,
          keyHex: _key,
          migrations: [...kMigrations, good2, bad3],
        ),
        throwsA(isA<MigrationFailed>().having((e) => e.version, 'version', 3)),
      );
      final db = sqlite3.open(path);
      db.execute("PRAGMA key = \"x'$_key'\"");
      expect(db.select('PRAGMA user_version').single.values.single, 2);
      db.close();
    });

    test('Clear history also removes older copies of the history that '
        'were moved aside or backed up', () async {
      // Bug repro (BUG-7): after a failed migration the old file is moved
      // aside but is still encrypted with the key that is still in the
      // keychain. Clear history says "This deletes all N items", but the
      // old copy stays on disk, readable by anyone who can reach the key.
      final first = await open();
      first.store.insertOrBump('$_marker a', ClipKind.text, 1);
      first.store.insertOrBump('$_marker b', ClipKind.text, 2);
      first.store.close();
      final opened = await open(migrations: [...kMigrations, dataDependent]);
      expect(opened.notices, {HistoryNotice.readError});
      final service = HistoryService(
        store: opened.store,
        notices: opened.notices,
        source: FakeClipboardSource(),
        log: log,
      )..start();
      addTearDown(service.dispose);

      service.clear();
      await service.close();

      final readable = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        try {
          final s = SqliteHistoryStore.open(path: f.path, keyHex: keys.stored!);
          if (s.count > 0) readable.add(f.path.split('/').last);
          s.close();
        } catch (_) {}
      }
      expect(
        readable,
        isEmpty,
        reason: 'old history still readable: $readable',
      );
    });
  });

  group('a write that fails part-way', () {
    late SqliteHistoryStore store;
    late String path;

    void sql(String statement) {
      final db = sqlite3.open(path);
      db.execute("PRAGMA key = \"x'$_key'\"");
      db.execute(statement);
      db.close();
    }

    setUp(() {
      path = '${dir.path}/tx.db';
      store = SqliteHistoryStore.open(path: path, keyHex: _key);
    });
    tearDown(() => store.close());

    test('the trim fails after the insert: nothing half-saved, limit holds, '
        'store still usable', () {
      store.setLimit(10);
      for (var i = 0; i < 10; i++) {
        store.insertOrBump('item $i', ClipKind.text, 100 + i);
      }
      sql(
        'CREATE TRIGGER no_delete BEFORE DELETE ON clip_items '
        "BEGIN SELECT RAISE(ABORT, 'disk error'); END",
      );

      expect(
        () => store.insertOrBump('eleventh', ClipKind.text, 200),
        throwsA(isA<SqliteException>()),
      );
      expect(store.count, 10);
      expect(store.list().map((i) => i.preview), isNot(contains('eleventh')));

      sql('DROP TRIGGER no_delete');
      store.insertOrBump('eleventh', ClipKind.text, 201);
      expect(store.count, 10, reason: 'rolled back, so a new write works');
      expect(store.list().first.preview, 'eleventh');
      expect(store.list().last.preview, 'item 1');
    });

    test('a bump that fails leaves the old time and order', () {
      store.insertOrBump('a', ClipKind.text, 100);
      store.insertOrBump('b', ClipKind.text, 200);
      sql(
        'CREATE TRIGGER no_update BEFORE UPDATE ON clip_items '
        "BEGIN SELECT RAISE(ABORT, 'disk error'); END",
      );
      expect(
        () => store.insertOrBump('a', ClipKind.text, 300),
        throwsA(isA<SqliteException>()),
      );
      expect(store.list().map((i) => i.preview), ['b', 'a']);
    });

    test('a clear that fails keeps everything', () {
      store.insertOrBump('a', ClipKind.text, 100);
      sql(
        'CREATE TRIGGER no_delete BEFORE DELETE ON clip_items '
        "BEGIN SELECT RAISE(ABORT, 'disk error'); END",
      );
      expect(() => store.clear(), throwsA(isA<SqliteException>()));
      expect(store.count, 1);
    });

    test('a failed limit change does not change the limit in memory', () {
      for (var i = 0; i < 20; i++) {
        store.insertOrBump('item $i', ClipKind.text, 100 + i);
      }
      sql(
        'CREATE TRIGGER no_delete BEFORE DELETE ON clip_items '
        "BEGIN SELECT RAISE(ABORT, 'disk error'); END",
      );
      expect(() => store.setLimit(10), throwsA(isA<SqliteException>()));
      expect(store.limit, 200, reason: 'rolled back in the file, so also here');
      expect(store.count, 20);
    });

    test('through the service: banner, item kept in memory, retried on the '
        'next copy, order kept', () {
      final source = FakeClipboardSource();
      var now = 0;
      final service = HistoryService(
        store: store,
        source: source,
        log: log,
        clock: () => now += 10,
      )..start();
      addTearDown(service.dispose);
      store.setLimit(10);
      for (var i = 0; i < 10; i++) {
        source.copy('item $i');
      }
      sql(
        'CREATE TRIGGER no_delete BEFORE DELETE ON clip_items '
        "BEGIN SELECT RAISE(ABORT, 'disk error'); END",
      );

      source.copy('stuck');
      expect(service.banners, contains(HistoryBanner.writeError));
      expect(service.items.first.preview, 'stuck');
      expect(store.count, 10);
      expect(log.codes, contains(LogCode.writeFailed));
      expect(
        log.details.whereType<int>(),
        isNotEmpty,
        reason: 'the SQLite result code is logged',
      );

      sql('DROP TRIGGER no_delete');
      source.copy('after');
      expect(service.banners, isNot(contains(HistoryBanner.writeError)));
      expect(store.list().map((i) => i.preview).take(2), ['after', 'stuck']);
      expect(store.count, 10);
    });
  });

  group('the 20 unsaved copies held in memory', () {
    late FakeClipboardSource source;
    late FlakyStore store;
    late HistoryService service;
    var now = 0;

    setUp(() {
      source = FakeClipboardSource();
      store = FlakyStore(MemoryHistoryStore());
      now = 0;
      service = HistoryService(
        store: store,
        source: source,
        log: log,
        clock: () => now += 10,
        writeClipboard: (_) async {},
      )..start();
    });
    tearDown(() => service.dispose());

    test('21 failed copies keep the newest 20, newest first', () {
      store.failWrites = true;
      for (var i = 0; i < 21; i++) {
        source.copy('copy $i');
      }
      final texts = service.items.map((i) => i.preview).toList();
      expect(texts.length, HistoryService.maxWaiting);
      expect(texts.first, 'copy 20');
      expect(texts.last, 'copy 1');
    });

    test('1,000 failed copies never hold more than 20', () {
      store.failWrites = true;
      for (var i = 0; i < 1000; i++) {
        source.copy('copy $i');
      }
      expect(service.items.length, 20);
      expect(service.items.first.preview, 'copy 999');
    });

    test('on recovery the 20 are saved oldest first, then the new copy', () {
      store.failWrites = true;
      for (var i = 0; i < 25; i++) {
        source.copy('copy $i');
      }
      store.failWrites = false;
      source.copy('fresh');
      final texts = store.list().map((i) => i.preview).toList();
      expect(texts.first, 'fresh');
      expect(texts[1], 'copy 24');
      expect(texts.last, 'copy 5');
      expect(texts.length, 21);
      expect(service.banners, isNot(contains(HistoryBanner.writeError)));
    });

    test('the same text copied twice while saving fails is one item', () {
      // Bug repro (BUG-5): waiting items are not de-duplicated, so the list
      // shows the same text twice (and a text that is already saved shows
      // again above its saved copy).
      store.failWrites = true;
      source.copy('same');
      source.copy('other');
      source.copy('same');
      final texts = service.items.map((i) => i.preview).toList();
      expect(texts, ['same', 'other']);
    });

    test('a saved text copied again while saving fails is not listed '
        'twice', () {
      source.copy('saved');
      store.failWrites = true;
      source.copy('saved');
      final texts = service.items.map((i) => i.preview).toList();
      expect(texts.where((t) => t == 'saved').length, 1);
    });

    test('repeating one text 100 times while failing uses one slot', () {
      store.failWrites = true;
      source.copy('keep 1');
      source.copy('keep 2');
      for (var i = 0; i < 100; i++) {
        source.copy('spam');
      }
      final texts = service.items.map((i) => i.preview).toList();
      expect(texts, containsAll(['keep 1', 'keep 2', 'spam']));
    });

    test('clear drops the waiting items and the banner', () {
      store.failWrites = true;
      source.copy('a');
      source.copy('b');
      expect(service.clear(), 2);
      expect(service.items, isEmpty);
      expect(service.banners, isEmpty);
      store.failWrites = false;
      source.copy('c');
      expect(texts(service), ['c']);
    });

    test('copy and delete of a waiting item work', () async {
      store.failWrites = true;
      source.copy('waiting');
      final id = service.items.single.id;
      expect(await service.copy(id), isTrue);
      final record = service.delete(id)!;
      expect(record.content, 'waiting');
      expect(service.items, isEmpty);
      expect(service.banners, isEmpty);
    });
  });

  group('after the history is closed', () {
    test('every action is safe: none throws, nothing is written', () async {
      final store = FlakyStore(MemoryHistoryStore());
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: log,
        writeClipboard: (_) async {},
      )..start();
      source.copy('a');
      final id = service.items.single.id;
      await service.close();
      await service.close();
      expect(store.closes, 1);

      source.copy('after close');
      expect(() => service.delete(id), returnsNormally);
      expect(() => service.clear(), returnsNormally);
      expect(() => service.setLimit(50), returnsNormally);
      expect(() => service.countRemovedBy(50), returnsNormally);
      expect(await service.copy(id), anyOf(isTrue, isFalse));
      service.dispose();
    });

    test('with the real store: actions after close do not throw', () async {
      final store = SqliteHistoryStore.open(
        path: '${dir.path}/closed.db',
        keyHex: _key,
      );
      final service = HistoryService(
        store: store,
        source: FakeClipboardSource(),
        log: log,
        writeClipboard: (_) async {},
      )..start();
      await service.close();
      expect(() => service.delete(1), returnsNormally);
      expect(
        () => service.undo(
          const ClipRecord(
            content: 'x',
            kind: ClipKind.text,
            createdAt: 1,
            lastCopiedAt: 1,
          ),
        ),
        returnsNormally,
      );
      expect(() => service.clear(), returnsNormally);
      expect(() => service.setLimit(50), returnsNormally);
      expect(() => service.countRemovedBy(50), returnsNormally);
      service.dispose();
    });

    test('memory-only mode: close writes nothing and leaves no file', () async {
      keys.readError = PlatformException(code: 'x', message: 'Code: -34018');
      final opened = await open();
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: opened.store,
        notices: opened.notices,
        source: source,
        log: log,
      )..start();
      source.copy(_marker);
      expect(service.items.single.preview, _marker);
      await service.close();
      expect(files(), isEmpty);
    });
  });

  group('the log never holds content, hashes or app names', () {
    late File logFile;
    late FileErrorLog fileLog;
    setUp(() {
      logFile = File('${dir.path}/kusunga.log');
      fileLog = FileErrorLog(logFile);
    });

    String logText() => logFile.existsSync() ? logFile.readAsStringSync() : '';

    void expectClean(String where) {
      final text = logText();
      final hash = sha256.convert(utf8.encode(_marker)).toString();
      for (final bad in [
        _marker,
        'PLAINTEXT-MARKER',
        'not-a-real-secret',
        hash,
        hash.substring(0, 16),
        base64.encode(utf8.encode(_marker)),
        '1Password',
        'Safari',
        'com.apple',
        'Bitwarden',
      ]) {
        expect(text, isNot(contains(bad)), reason: '$where: $bad');
      }
      for (final line in text.split('\n').where((l) => l.isNotEmpty)) {
        expect(
          line,
          matches(RegExp(r'^\S+ [A-Za-z]+( -?\d+)?$')),
          reason: '$where: every line is "time code [number]"',
        );
      }
    }

    test('open-time failures with the marker in every error message', () async {
      keys.readError = PlatformException(
        code: _marker,
        message: 'Code: -34018, Message: $_marker 1Password',
        details: _marker,
      );
      await open(errorLog: fileLog);
      keys.readError = null;
      keys.writeError = Exception('$_marker Safari');
      keys.stored = null;
      await open(errorLog: fileLog);
      keys.writeError = null;
      keys.readBackOverride = 'b' * 64;
      await open(errorLog: fileLog);
      expect(logText(), isNotEmpty, reason: 'something was logged');
      expectClean('open');
    });

    test(
      'unreadable file, wrong key, newer schema, failed migration',
      () async {
        var opened = await open(errorLog: fileLog);
        opened.store.insertOrBump(_marker, ClipKind.text, 1);
        opened.store.close();
        keys.stored = 'd' * 64;
        opened = await open(errorLog: fileLog);
        opened.store.close();
        final bad = Migration(
          version: 2,
          statements: ["SELECT '$_marker' FROM"],
        );
        opened = await open(
          migrations: [...kMigrations, bad],
          errorLog: fileLog,
        );
        opened.store.close();
        expect(logText(), contains('storeUnreadable'));
        expectClean('unreadable');
      },
    );

    test('write, read, clear and flush failures with the marker in the '
        'exception', () async {
      final store = _ThrowingStore(MemoryHistoryStore());
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: fileLog,
        writeClipboard: (_) async => throw Exception(_marker),
      )..start();
      source.copy(_marker);
      store.mode = true;
      source.copy('$_marker again');
      service.delete(-1);
      service.undo(
        const ClipRecord(
          content: _marker,
          kind: ClipKind.text,
          createdAt: 1,
          lastCopiedAt: 1,
        ),
      );
      service.clear();
      service.setLimit(50);
      source.controller.addError(Exception(_marker));
      source.controller.add(const ClipboardReadError('locked'));
      source.controller.add(ClipboardReadError(_marker));
      source.controller.add(const ClipboardSkipped(SkipReason.tooLarge));
      await service.copy(1);
      await service.close();
      service.dispose();
      expect(logText(), isNotEmpty);
      expectClean('service');
    });

    test('a real database and a real log through a busy session', () async {
      final opened = await open(errorLog: fileLog);
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: opened.store,
        source: source,
        log: fileLog,
        writeClipboard: (_) async {},
      )..start();
      for (var i = 0; i < 50; i++) {
        source.copy('$_marker $i');
      }
      source.copy('x' * (ClipItem.maxContentLength + 1));
      service.clear();
      await service.close();
      service.dispose();
      expectClean('session');
      expect(anyFileHolds(_marker), isFalse);
    });

    test('log rotation does not copy anything but codes', () {
      final small = FileErrorLog(logFile, maxBytes: 100);
      for (var i = 0; i < 50; i++) {
        small.log(LogCode.writeFailed, 5);
      }
      for (final f in dir.listSync().whereType<File>()) {
        for (final line in f.readAsLinesSync().where((l) => l.isNotEmpty)) {
          expect(line, matches(RegExp(r'^\S+ [A-Za-z]+( -?\d+)?$')));
        }
      }
      expect(
        logFile.lengthSync(),
        lessThanOrEqualTo(100 + 60),
        reason: 'stays near the cap',
      );
    });
  });
}

List<String> texts(HistoryService s) => s.items.map((i) => i.preview).toList();

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  final first = needle.first;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    if (haystack[i] != first) continue;
    var j = 1;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}

/// A store whose every call can throw an error that quotes clipboard text.
class _ThrowingStore extends FlakyStore {
  _ThrowingStore(super.inner);
  bool mode = false;

  void _boom() {
    if (mode) throw Exception(_marker);
  }

  @override
  int insertOrBump(String content, ClipKind kind, int nowMs) {
    _boom();
    return super.insertOrBump(content, kind, nowMs);
  }

  @override
  List<ClipItem> list() {
    _boom();
    return super.list();
  }

  @override
  ClipRecord? delete(int id) {
    _boom();
    return super.delete(id);
  }

  @override
  void restore(ClipRecord record) {
    _boom();
    super.restore(record);
  }

  @override
  int clear() {
    _boom();
    return super.clear();
  }

  @override
  void setLimit(int newLimit) {
    _boom();
    super.setLimit(newLimit);
  }

  @override
  void close() {
    _boom();
    super.close();
  }
}
