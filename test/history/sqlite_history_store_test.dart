import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:sqlite3/sqlite3.dart';

import 'store_contract.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _otherKey =
    'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

void main() {
  runStoreContract('SqliteHistoryStore', () {
    final dir = Directory.systemTemp.createTempSync('kusunga_contract_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = SqliteHistoryStore.open(
      path: '${dir.path}/kusunga.db',
      keyHex: _key,
    );
    // Windows cannot delete an open file: close before the folder goes.
    addTearDown(store.close);
    return store;
  });

  group('SqliteHistoryStore on disk', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kusunga_store_');
      path = '${dir.path}/kusunga.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('schema version is 4 and the tables match the design', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final db = sqlite3.open(path);
      db.execute("PRAGMA hexkey = '$_key'");
      expect(db.select('PRAGMA user_version').single.values.single, 4);
      final cols = db
          .select('PRAGMA table_info(clip_items)')
          .map((r) => r['name'])
          .toList();
      expect(
        cols,
        containsAll([
          'id',
          'content',
          'kind',
          'content_hash',
          'created_at',
          'last_copied_at',
        ]),
      );
      expect(cols, isNot(contains('source_app')));
      expect(
        db.select('PRAGMA index_list(clip_items)').map((r) => r['name']),
        contains('idx_clip_items_last_copied_at'),
      );
      db.close();
    });

    test('the database rejects a bad kind, empty text and a bad limit', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final db = sqlite3.open(path);
      db.execute("PRAGMA hexkey = '$_key'");
      final hash = Uint8List(32);
      expect(
        () => db.execute(
          'INSERT INTO clip_items (content, kind, content_hash, created_at, '
          "last_copied_at) VALUES ('a', 'image', ?, 1, 1)",
          [hash],
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute(
          'INSERT INTO clip_items (content, kind, content_hash, created_at, '
          "last_copied_at) VALUES ('', 'text', ?, 1, 1)",
          [hash],
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute(
          "INSERT INTO settings (key, value) VALUES ('history_limit', 9)",
        ),
        throwsA(isA<SqliteException>()),
      );
      db.close();
    });

    test('items survive close and reopen with the same key', () {
      final a = SqliteHistoryStore.open(path: path, keyHex: _key);
      a.insertOrBump('keep me', ClipKind.text, 1);
      a.setLimit(50);
      a.close();

      final b = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(b.list().single.preview, 'keep me');
      expect(b.limit, 50);
      b.close();
    });

    test('the file is unreadable without the key', () {
      const marker = 'UNIQUE-MARKER-4f9c1d2e-not-a-real-secret';
      final s = SqliteHistoryStore.open(path: path, keyHex: _key);
      s.insertOrBump(marker, ClipKind.text, 1);
      s.close();

      final bytes = File(path).readAsBytesSync();
      expect(String.fromCharCodes(bytes), isNot(contains(marker)));
      expect(
        String.fromCharCodes(bytes.take(15)),
        isNot('SQLite format 3'),
        reason: 'an encrypted file has no plain SQLite header',
      );

      final plain = sqlite3.open(path);
      expect(
        () => plain.select('SELECT count(*) FROM sqlite_master'),
        throwsA(isA<SqliteException>()),
      );
      plain.close();
    });

    test('the key is used raw (PRAGMA hexkey): the passphrase form fails', () {
      final s = SqliteHistoryStore.open(path: path, keyHex: _key);
      s.insertOrBump('raw key', ClipKind.text, 1);
      s.close();

      final passphrase = sqlite3.open(path);
      passphrase.execute("PRAGMA cipher = 'chacha20'");
      passphrase.execute("PRAGMA key = \"x'$_key'\"");
      expect(
        () => passphrase.select('SELECT count(*) FROM sqlite_master'),
        throwsA(isA<SqliteException>()),
        reason:
            'key="x\'..\'" is a passphrase for this cipher, not the raw key',
      );
      passphrase.close();

      final raw = sqlite3.open(path);
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute("PRAGMA hexkey = '$_key'");
      expect(raw.select('SELECT count(*) AS n FROM clip_items').single['n'], 1);
      raw.close();
    });

    test('a wrong key fails to open and leaves the file alone', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final before = File(path).readAsBytesSync();
      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: _otherKey),
        throwsA(isA<SqliteException>()),
      );
      expect(File(path).readAsBytesSync(), before);
    });

    test('a corrupt file fails to open', () {
      File(path).writeAsBytesSync(List.filled(4096, 7));
      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: _key),
        throwsA(isA<SqliteException>()),
      );
    });

    test('refuses to store when the cipher is not active', () {
      expect(
        () => SqliteHistoryStore.open(
          path: path,
          keyHex: _key,
          cipherActive: (_) => false,
        ),
        throwsA(isA<EncryptionUnavailable>()),
      );
      expect(File(path).existsSync(), isFalse, reason: 'nothing is written');
    });

    test('a bad key format is refused', () {
      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: 'abc'),
        throwsArgumentError,
      );
      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: "x' OR 1=1 --"),
        throwsArgumentError,
      );
    });
  });

  group('migrations', () {
    late Directory dir;
    late String path;
    // A later step than the shipped ones (version 3 is the snippets step, 4 typed shortcuts).
    final v2 = Migration(
      version: 5,
      statements: ['ALTER TABLE clip_items ADD COLUMN note TEXT'],
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kusunga_migrate_');
      path = '${dir.path}/kusunga.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    int version() {
      final db = sqlite3.open(path);
      db.execute("PRAGMA hexkey = '$_key'");
      final v = db.select('PRAGMA user_version').single.values.single as int;
      db.close();
      return v;
    }

    test('data survives a later migration; the backup is removed', () {
      final a = SqliteHistoryStore.open(path: path, keyHex: _key);
      a.insertOrBump('old data', ClipKind.text, 1);
      a.close();

      final b = SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: [...kMigrations, v2],
      );
      expect(b.list().single.preview, 'old data');
      b.close();
      expect(version(), 5);
      expect(File('$path.bak').existsSync(), isFalse);
    });

    test('the real v1 to v2 step keeps every item, time and the limit', () {
      final v1 = SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: kMigrations.sublist(0, 1),
      );
      expect(kMigrations[1].statements, isEmpty, reason: 'the picker step');
      v1.setLimit(50);
      for (var i = 0; i < 30; i++) {
        v1.insertOrBump('item $i', i.isEven ? ClipKind.text : ClipKind.link, i);
      }
      final before = v1.list();
      v1.close();
      expect(version(), 1);

      final v2store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final after = v2store.list();
      expect(after.length, 30);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].preview, before[i].preview);
        expect(after[i].kind, before[i].kind);
        expect(after[i].createdAt, before[i].createdAt);
        expect(after[i].lastCopiedAt, before[i].lastCopiedAt);
      }
      expect(v2store.limit, 50);
      expect(v2store.readSetting('picker_shortcut'), isNull);
      v2store.writeSetting('picker_shortcut', 'ctrl+alt+k');
      v2store.close();
      expect(version(), 4);
      expect(File('$path.bak').existsSync(), isFalse);

      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(again.readSetting('picker_shortcut'), 'ctrl+alt+k');
      expect(again.count, 30);
      again.close();
    });

    test('a backup copy exists while the migration runs', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      var backupSeen = false;
      final spy = Migration(
        version: 5,
        statements: ['ALTER TABLE clip_items ADD COLUMN note TEXT'],
        onRun: () => backupSeen = File('$path.bak').existsSync(),
      );
      SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: [...kMigrations, spy],
      ).close();
      expect(backupSeen, isTrue);
    });

    test('a failing migration rolls back and keeps the backup', () {
      final a = SqliteHistoryStore.open(path: path, keyHex: _key);
      a.insertOrBump('old data', ClipKind.text, 1);
      a.close();

      final bad = Migration(
        version: 5,
        statements: [
          'ALTER TABLE clip_items ADD COLUMN note TEXT',
          'THIS IS NOT SQL',
        ],
      );
      expect(
        () => SqliteHistoryStore.open(
          path: path,
          keyHex: _key,
          migrations: [...kMigrations, bad],
        ),
        throwsA(isA<MigrationFailed>()),
      );
      expect(version(), 4);
      expect(File('$path.bak').existsSync(), isTrue);

      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(again.list().single.preview, 'old data');
      again.close();
    });

    test('a database from a newer app is not touched', () {
      SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: [...kMigrations, v2],
      ).close();
      expect(
        () => SqliteHistoryStore.open(path: path, keyHex: _key),
        throwsA(isA<UnsupportedSchemaVersion>()),
      );
      expect(version(), 5);
    });

    test('migration versions start at 1 and have no gaps', () {
      for (var i = 0; i < kMigrations.length; i++) {
        expect(kMigrations[i].version, i + 1);
      }
    });
  });
}
