// M1.10b (tester): files written by SQLite3 Multiple Ciphers 2.5.0 (the two
// kept in test/data/fixtures, SHA-256 pinned in frozen_db_fixture_test.dart)
// meet the new library (2.7.1) in the ways that could harm a user's history:
// a wrong key, a key in another format, a damaged or cut-off file, leftover
// journal files. The rule for every case: the open fails or succeeds as the
// design note says, and the bytes of the user's file are never changed by a
// failed open; the app's own start-up (`openHistory`) keeps the unreadable
// file aside with its bytes intact instead of overwriting it.
//
// All files are copies in a temporary folder: the kept fixtures are only
// read. Paths are built with `package:path` so they hold on Windows.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

// The made-up key the fixtures were written with.
const _key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

final _v6 = p.join('test', 'data', 'fixtures', 'frozen_v6_sqlite3mc_2_5_0.db');
final _v3 = p.join('test', 'data', 'fixtures', 'frozen_v3_sqlite3mc_2_5_0.db');

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory dir;
  late String path;
  final stores = <SqliteHistoryStore>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_oldlib_');
    path = p.join(dir.path, 'kusunga.db');
  });
  tearDown(() {
    // Windows cannot delete an open file: close every store first.
    for (final s in stores) {
      s.close();
    }
    stores.clear();
    dir.deleteSync(recursive: true);
  });

  /// A copy of [fixture] at [path], and its bytes.
  Uint8List put(String fixture) {
    File(fixture).copySync(path);
    return File(path).readAsBytesSync();
  }

  List<String> names() =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  void expectUntouched(Uint8List before, {String? reason}) {
    expect(
      _digest(File(path).readAsBytesSync()),
      _digest(before),
      reason: reason ?? 'a failed open changed the file',
    );
    // Nothing else was left next to the file: no backup, journal or WAL.
    expect(names(), ['kusunga.db'], reason: reason);
  }

  group('a wrong key', () {
    // Right length, wrong value. Including a key that differs in the last
    // hex digit only, and the right key reversed.
    final wrongKeys = <String, String>{
      'all zeros': '0' * 64,
      'all f': 'f' * 64,
      'last digit differs': '${_key.substring(0, 63)}1',
      'first digit differs': '2${_key.substring(1)}',
      'reversed': _key.split('').reversed.join(),
    };

    for (final (name, file) in [('version 6', _v6), ('version 3', _v3)]) {
      for (final e in wrongKeys.entries) {
        test('${e.key} fails on the $name file written by 2.5.0 and leaves '
            'its bytes alone', () {
          final before = put(file);
          expect(
            () => SqliteHistoryStore.open(path: path, keyHex: e.value),
            throwsA(isA<SqliteException>()),
          );
          expectUntouched(before);
        });
      }
    }

    test('many wrong keys in a row never change the file, and the right '
        'key still opens it', () {
      final before = put(_v6);
      final random = Random(7);
      for (var i = 0; i < 25; i++) {
        final k = generateKeyHex(random);
        expect(
          () => SqliteHistoryStore.open(path: path, keyHex: k),
          throwsA(isA<SqliteException>()),
          reason: k.isEmpty ? '' : 'try $i',
        );
      }
      expectUntouched(before);
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      stores.add(store);
      expect(store.limit, 321);
    });
  });

  group('a key in another form', () {
    test('an empty key, a short and a long one, non-hex text and a quote '
        'are refused before the file is touched, and never named in the '
        'error', () {
      final before = put(_v6);
      for (final bad in [
        '',
        _key.substring(1),
        '${_key}0',
        'g' * 64,
        '${_key.substring(0, 62)}\';',
        ' $_key',
        '$_key\n',
        'x\'$_key\'',
      ]) {
        try {
          SqliteHistoryStore.open(path: path, keyHex: bad);
          fail('opened with a key that is not 64 hex digits: "$bad"');
        } on ArgumentError catch (e) {
          // The key is a secret: not in the message, even a wrong one.
          expect(e.toString(), isNot(contains(_key.substring(0, 20))));
          if (bad.isNotEmpty) expect(e.toString(), isNot(contains(bad)));
        }
      }
      expectUntouched(before);
    });

    test('the same key in capital letters is the same key and opens the '
        'file', () {
      put(_v6);
      final store = SqliteHistoryStore.open(
        path: path,
        keyHex: _key.toUpperCase(),
      );
      stores.add(store);
      expect(store.limit, 321);
    });

    test('the key as a passphrase (key, or the x\'..\' form) is a different '
        'key: it does not read the file, and the file is unchanged', () {
      final before = put(_v6);
      for (final setKey in [
        "PRAGMA key = '$_key'",
        "PRAGMA key = \"x'$_key'\"",
      ]) {
        final db = sqlite3.open(path);
        try {
          db.execute("PRAGMA cipher = 'chacha20'");
          db.execute(setKey);
          expect(
            () => db.select('SELECT count(*) FROM sqlite_master'),
            throwsA(isA<SqliteException>()),
            reason: setKey.split('=').first,
          );
        } finally {
          db.close();
        }
      }
      expectUntouched(before);
    });

    test('opening with no key reads nothing from the file', () {
      final before = put(_v6);
      final db = sqlite3.open(path);
      try {
        expect(
          () => db.select('SELECT count(*) FROM sqlite_master'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        db.close();
      }
      expectUntouched(before);
    });
  });

  group('a damaged file written by 2.5.0', () {
    Uint8List cut(Uint8List b, int length) =>
        Uint8List.fromList(b.sublist(0, length));

    final damage = <String, Uint8List Function(Uint8List)>{
      'cut to 100 bytes': (b) => cut(b, 100),
      'cut to the first page only': (b) => cut(b, 4096),
      'cut to half': (b) => cut(b, b.length ~/ 2),
      'cut in the middle of a page': (b) => cut(b, b.length - 1000),
      'one byte flipped in the middle': (b) {
        final c = Uint8List.fromList(b);
        c[b.length ~/ 2] ^= 0x01;
        return c;
      },
      'the last page replaced by zeros': (b) {
        final c = Uint8List.fromList(b);
        c.fillRange(b.length - 4096, b.length, 0);
        return c;
      },
      'a page of another file spliced in': (b) {
        final c = Uint8List.fromList(b);
        final other = File(_v3).readAsBytesSync();
        c.setRange(8192, 12288, other.sublist(8192, 12288));
        return c;
      },
    };

    for (final e in damage.entries) {
      test('${e.key}: the open fails and the file is not written to', () {
        final good = File(_v6).readAsBytesSync();
        final bad = e.value(good);
        expect(_digest(bad), isNot(_digest(good)));
        File(path).writeAsBytesSync(bad);
        // Only these two errors mean "unreadable" (openHistory then keeps
        // the file aside): the library's own error, or the store's
        // quick_check failing. Any other error is a bug, not damage.
        expect(
          () => SqliteHistoryStore.open(path: path, keyHex: _key),
          throwsA(
            anyOf(
              isA<SqliteException>(),
              isA<StateError>().having(
                (e) => e.message,
                'message',
                'store damaged',
              ),
            ),
          ),
        );
        expectUntouched(bad, reason: e.key);
      });
    }

    test('the app start-up keeps a damaged file aside byte for byte and '
        'starts a new history instead of overwriting it', () async {
      final good = File(_v6).readAsBytesSync();
      final bad = Uint8List.fromList(good)..[good.length ~/ 2] ^= 0x01;
      File(path).writeAsBytesSync(bad);
      final log = FakeLog();
      final opened = await openHistory(
        keys: FakeKeyStore(stored: _key),
        directory: dir.path,
        log: log,
        today: () => DateTime(2026, 11, 24),
      );
      stores.add(opened.store as SqliteHistoryStore);
      expect(opened.notices, {HistoryNotice.readError});
      expect(log.codes, contains(LogCode.storeUnreadable));
      final aside = File(p.join(dir.path, 'kusunga.db.unreadable-2026-11-24'));
      expect(aside.existsSync(), isTrue);
      expect(_digest(aside.readAsBytesSync()), _digest(bad));
      // The new history is a different, empty file.
      expect(opened.store.count, 0);
      expect(_digest(File(path).readAsBytesSync()), isNot(_digest(bad)));
    });
  });

  group('the app start-up on the file written by 2.5.0', () {
    test('with the existing key: no notice, no error logged, nothing moved '
        'aside, and the file is byte for byte the one that was kept', () async {
      final before = put(_v6);
      final log = FakeLog();
      final opened = await openHistory(
        keys: FakeKeyStore(stored: _key),
        directory: dir.path,
        log: log,
      );
      stores.add(opened.store as SqliteHistoryStore);
      expect(opened.notices, isEmpty);
      expect(log.codes, isEmpty);
      expect(opened.store.count, greaterThan(0));
      (opened.store as SqliteHistoryStore).close();
      stores.clear();
      expectUntouched(before);
    });

    test('with a wrong key: "can\'t open your history" (the read error '
        'notice), the whole file is kept aside unchanged and no new history '
        'is written over it', () async {
      final before = put(_v6);
      final log = FakeLog();
      final opened = await openHistory(
        keys: FakeKeyStore(stored: 'f' * 64),
        directory: dir.path,
        log: log,
        today: () => DateTime(2026, 11, 24),
      );
      stores.add(opened.store as SqliteHistoryStore);
      expect(opened.notices, {HistoryNotice.readError});
      expect(log.codes, [LogCode.storeUnreadable]);
      final aside = File(p.join(dir.path, 'kusunga.db.unreadable-2026-11-24'));
      expect(_digest(aside.readAsBytesSync()), _digest(before));
      // And the pinned fixture hash says the bytes are the old library's.
      expect(
        _digest(aside.readAsBytesSync()),
        '5423421838e41f0e35df93de79832aca4ff706b1448a1445eb4dcc321ab24709',
      );
      expect(opened.store.count, 0);
    });

    test('a second start-up on the same day does not overwrite the kept '
        'file: it is kept as -2', () async {
      final before = put(_v6);
      Future<void> start() async {
        final opened = await openHistory(
          keys: FakeKeyStore(stored: 'f' * 64),
          directory: dir.path,
          log: FakeLog(),
          today: () => DateTime(2026, 11, 24),
        );
        (opened.store as SqliteHistoryStore).close();
      }

      await start();
      // The user puts the old file back and tries again with the wrong key.
      File(p.join(dir.path, 'kusunga.db.unreadable-2026-11-24')).copySync(path);
      await start();
      for (final n in ['', '-2']) {
        final f = File(p.join(dir.path, 'kusunga.db.unreadable-2026-11-24$n'));
        expect(_digest(f.readAsBytesSync()), _digest(before), reason: n);
      }
    });
  });

  group('leftovers', () {
    test('empty -journal and -wal files next to the file from 2.5.0 do not '
        'stop it opening or change its rows', () {
      put(_v6);
      File('$path-journal').writeAsBytesSync(const []);
      File('$path-wal').writeAsBytesSync(const []);
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      stores.add(store);
      expect(store.limit, 321);
      expect(store.count, greaterThan(0));
    });

    test('a -wal file of garbage next to the file is ignored by the open '
        'and the main file is not changed', () {
      final before = put(_v6);
      File('$path-wal').writeAsBytesSync(List.filled(4096, 0xAB));
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      store.close();
      expect(_digest(File(path).readAsBytesSync()), _digest(before));
    });
  });

  group('the new library on the kept files', () {
    test('25 opens and closes in a row leave the version 6 file byte for '
        'byte unchanged', () {
      final before = put(_v6);
      for (var i = 0; i < 25; i++) {
        SqliteHistoryStore.open(path: path, keyHex: _key).close();
      }
      expectUntouched(before);
    });

    test('a write on the new library changes the file, and a copy of the '
        'kept file stays what 2.5.0 wrote (the write is to the copy only)', () {
      final before = put(_v6);
      final fixtureDigest = _digest(File(_v6).readAsBytesSync());
      var store = SqliteHistoryStore.open(path: path, keyHex: _key);
      store.snippetStore().insert(
        name: 'tester',
        content: 'written by 2.7.1',
        type: SnippetType.other,
        nowMs: 1,
      );
      store.close();
      store = SqliteHistoryStore.open(path: path, keyHex: _key);
      stores.add(store);
      expect(
        store.snippetStore().list().map((s) => s.name),
        contains('tester'),
      );
      expect(_digest(File(path).readAsBytesSync()), isNot(_digest(before)));
      expect(_digest(File(_v6).readAsBytesSync()), fixtureDigest);
      // The file written by the new library is still encrypted: not a plain
      // SQLite file.
      final head = File(path).readAsBytesSync().sublist(0, 15);
      expect(String.fromCharCodes(head), isNot('SQLite format 3'));
    });

    test('the file written by the new library is opened by no other key, '
        'and not without one', () {
      put(_v6);
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: '0' * 64),
        throwsA(isA<SqliteException>()),
      );
      final db = sqlite3.open(path);
      try {
        expect(
          () => db.select('SELECT 1 FROM sqlite_master'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        db.close();
      }
    });
  });
}
