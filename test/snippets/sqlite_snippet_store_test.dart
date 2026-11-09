import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/sqlite_snippet_store.dart';
import 'package:sqlite3/sqlite3.dart';

import 'snippet_store_contract.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  runSnippetStoreContract('SqliteSnippetStore', () {
    final dir = Directory.systemTemp.createTempSync('kusunga_snip_contract_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final history = SqliteHistoryStore.open(
      path: '${dir.path}/kusunga.db',
      keyHex: _key,
    );
    addTearDown(history.close);
    return history.snippetStore();
  });

  group('snippets table (schema version 3)', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kusunga_snip_');
      path = '${dir.path}/kusunga.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Database raw() {
      final db = sqlite3.open(path);
      db.execute("PRAGMA hexkey = '$_key'");
      return db;
    }

    int version() {
      final db = raw();
      final v = db.select('PRAGMA user_version').single.values.single as int;
      db.close();
      return v;
    }

    test('version 3 adds only the snippets table, as in the design', () {
      SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: kMigrations.sublist(0, 3),
      ).close();
      final db = raw();
      expect(db.select('PRAGMA user_version').single.values.single, 3);
      expect(db.select('PRAGMA table_info(snippets)').map((r) => r['name']), [
        'id',
        'name',
        'content',
        'type',
        'position',
        'created_at',
        'updated_at',
      ]);
      expect(
        db.select('PRAGMA index_list(snippets)').map((r) => r['name']),
        contains('idx_snippets_position'),
      );
      // Nothing was added to the history tables.
      expect(db.select('PRAGMA table_info(clip_items)').map((r) => r['name']), [
        'id',
        'content',
        'kind',
        'content_hash',
        'created_at',
        'last_copied_at',
      ]);
      expect(db.select('PRAGMA table_info(settings)').map((r) => r['name']), [
        'key',
        'value',
      ]);
      db.close();
    });

    test('the database itself refuses bad rows', () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final db = raw();
      void insert(String name, String content, String type) => db.execute(
        'INSERT INTO snippets (name, content, type, position, created_at, '
        'updated_at) VALUES (?, ?, ?, 0, 1, 1)',
        [name, content, type],
      );
      insert('ok', 'ok', 'phone');
      for (final bad in [
        ('', 'x', 'other'),
        ('n' * 101, 'x', 'other'),
        ('x', '', 'other'),
        ('x', 'a' * (ClipItem.maxContentLength + 1), 'other'),
        ('x', 'x', 'card'),
      ]) {
        expect(
          () => insert(bad.$1, bad.$2, bad.$3),
          throwsA(isA<SqliteException>()),
          reason: '${bad.$1.length} ${bad.$2.length} ${bad.$3}',
        );
      }
      db.close();
    });

    test('v2 to v3 keeps every history item, time and setting', () {
      final v2 = SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: kMigrations.sublist(0, 2),
      );
      v2.setLimit(40);
      v2.writeSetting('picker_shortcut', 'ctrl+alt+k');
      v2.writeSetting('paste_mode', 'copy_only');
      for (var i = 0; i < 30; i++) {
        v2.insertOrBump('item $i', i.isEven ? ClipKind.text : ClipKind.link, i);
      }
      final before = v2.list();
      v2.close();
      expect(version(), 2);

      final v3 = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(version(), 4);
      final after = v3.list();
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].id, before[i].id);
        expect(after[i].preview, before[i].preview);
        expect(after[i].kind, before[i].kind);
        expect(after[i].createdAt, before[i].createdAt);
        expect(after[i].lastCopiedAt, before[i].lastCopiedAt);
      }
      expect(v3.limit, 40);
      expect(v3.readSetting('picker_shortcut'), 'ctrl+alt+k');
      expect(v3.readSetting('paste_mode'), 'copy_only');
      expect(v3.snippetStore().count, 0);
      v3.close();
      expect(File('$path.bak').existsSync(), isFalse);
    });

    test('a v2 build leaves a v3 file untouched', () {
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      store.snippetStore().insert(
        name: 'Mine',
        content: 'kept',
        type: SnippetType.other,
        nowMs: 1,
      );
      store.close();
      final bytes = File(path).readAsBytesSync();
      expect(
        () => SqliteHistoryStore.open(
          path: path,
          keyHex: _key,
          migrations: kMigrations.sublist(0, 2),
        ),
        throwsA(isA<UnsupportedSchemaVersion>()),
      );
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('the history limit, a lower limit and Clear never touch snippets', () {
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      final snippets = store.snippetStore();
      for (var i = 0; i < 15; i++) {
        snippets.insert(
          name: 's$i',
          content: 'same as history $i',
          type: SnippetType.other,
          nowMs: i,
        );
      }
      store.setLimit(10);
      for (var i = 0; i < 40; i++) {
        store.insertOrBump('same as history ${i % 15}', ClipKind.text, 100 + i);
        store.insertOrBump('other $i', ClipKind.text, 200 + i);
      }
      expect(store.count, 10);
      expect(snippets.count, 15);
      store.clear();
      expect(store.count, 0);
      expect(snippets.count, 15);
      expect(snippets.contentOf(snippets.list().last.id), 'same as history 14');
      store.close();

      final again = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(again.snippetStore().count, 15);
      again.close();
    });

    test('snippet text is never in the file as plain text', () {
      final store = SqliteHistoryStore.open(path: path, keyHex: _key);
      store.snippetStore().insert(
        name: 'NameMarker12345',
        content: 'ContentMarker67890',
        type: SnippetType.phone,
        nowMs: 1,
      );
      store.close();
      final text = String.fromCharCodes(File(path).readAsBytesSync());
      expect(text, isNot(contains('NameMarker12345')));
      expect(text, isNot(contains('ContentMarker67890')));
      expect(text, isNot(contains('phone')));
    });

    group('a write that fails part-way leaves the old version', () {
      late Database db;
      late SqliteSnippetStore store;

      setUp(() {
        db = sqlite3.openInMemory();
        for (final m in kMigrations) {
          for (final sql in m.statements) {
            db.execute(sql);
          }
        }
        store = SqliteSnippetStore(db);
        for (final n in ['A', 'B', 'C', 'D']) {
          store.insert(name: n, content: n, type: SnippetType.other, nowMs: 1);
        }
      });
      tearDown(() => db.close());

      List<String> names() => store.list().map((s) => s.name).toList();

      test('a full disk (SQLITE_FULL) keeps its own error, and the store '
          'still works afterwards (F6)', () {
        final pages =
            db.select('PRAGMA page_count').single.values.single as int;
        db.execute('PRAGMA max_page_count = ${pages + 2}');
        final big = 'z' * 500000;
        Object? error;
        try {
          store.insert(
            name: 'Big',
            content: big,
            type: SnippetType.other,
            nowMs: 2,
          );
        } catch (e) {
          error = e;
        }
        expect(
          error,
          isA<SqliteException>().having((e) => e.resultCode, 'code', 13),
          reason: '$error',
        );
        expect(db.autocommit, isTrue, reason: 'no transaction left open');
        expect(names(), ['A', 'B', 'C', 'D']);
        db.execute('PRAGMA max_page_count = 1073741823');
        store.insert(
          name: 'E',
          content: 'e',
          type: SnippetType.other,
          nowMs: 3,
        );
        expect(names(), ['A', 'B', 'C', 'D', 'E']);
      });

      test('a ROLLBACK that itself fails never hides the first error', () {
        // A trigger aborts the update; the transaction is then rolled back.
        db.execute(
          'CREATE TEMP TRIGGER fail BEFORE UPDATE OF content ON snippets '
          "BEGIN SELECT RAISE(ROLLBACK, 'disk'); END",
        );
        final a = store.list().first.id;
        expect(
          () => store.update(
            a,
            name: 'A2',
            content: 'changed',
            type: SnippetType.email,
            nowMs: 9,
          ),
          throwsA(
            isA<SqliteException>().having((e) => e.message, 'message', 'disk'),
          ),
        );
        expect(db.autocommit, isTrue);
        expect(store.contentOf(a), 'A');
      });

      test('move', () {
        db.execute(
          'CREATE TEMP TRIGGER fail AFTER UPDATE OF position ON snippets '
          "WHEN NEW.position = 2 BEGIN SELECT RAISE(ABORT, 'disk'); END",
        );
        final d = store.list().last.id;
        expect(() => store.move(d, 0), throwsA(isA<SqliteException>()));
        expect(names(), ['A', 'B', 'C', 'D']);
        expect(store.list().map((s) => s.position), [0, 1, 2, 3]);
      });

      test('delete', () {
        db.execute(
          'CREATE TEMP TRIGGER fail AFTER UPDATE OF position ON snippets '
          "BEGIN SELECT RAISE(ABORT, 'disk'); END",
        );
        final a = store.list().first.id;
        expect(() => store.delete(a), throwsA(isA<SqliteException>()));
        expect(names(), ['A', 'B', 'C', 'D']);
      });

      test('update', () {
        db.execute(
          'CREATE TEMP TRIGGER fail BEFORE UPDATE OF content ON snippets '
          "BEGIN SELECT RAISE(ABORT, 'disk'); END",
        );
        final a = store.list().first.id;
        expect(
          () => store.update(
            a,
            name: 'A2',
            content: 'changed',
            type: SnippetType.email,
            nowMs: 9,
          ),
          throwsA(isA<SqliteException>()),
        );
        expect(store.list().first.name, 'A');
        expect(store.contentOf(a), 'A');
      });
    });
  });
}
