// Schema version 4 (M1.5, `docs/design/typed-shortcuts.md`, "Data"): the
// nullable `snippets.shortcut` column with its CHECK and unique index, the
// `ignored_apps` table seeded with the preset password managers, and the
// `typed_shortcuts_on` setting (off, PM decision D3 A).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:sqlite3/sqlite3.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_v4_');
    path = '${dir.path}/kusunga.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Database raw() => sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");

  test('version 4 adds the shortcut column, its index, ignored_apps and the '
      'setting', () {
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final db = raw();
    expect(
      db.select('PRAGMA user_version').single.values.single,
      kMigrations.last.version,
    );
    expect(
      db.select('PRAGMA table_info(snippets)').map((r) => r['name']),
      contains('shortcut'),
    );
    expect(
      db.select('PRAGMA index_list(snippets)').map((r) => r['name']),
      contains('idx_snippets_shortcut'),
    );
    expect(db.select('PRAGMA table_info(ignored_apps)').map((r) => r['name']), [
      'id',
      'app_id',
      'display_name',
      'preset',
    ]);
    expect(
      db
          .select("SELECT value FROM settings WHERE key = 'typed_shortcuts_on'")
          .single['value'],
      0,
    );
    db.close();
  });

  test('the seeded rows are exactly the preset list, all marked preset', () {
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final db = raw();
    final rows = db.select(
      'SELECT app_id, display_name, preset FROM ignored_apps ORDER BY id',
    );
    expect(
      [for (final r in rows) (r['app_id'], r['display_name'], r['preset'])],
      [for (final p in presetIgnoredApps) (p.appId, p.displayName, 1)],
    );
    db.close();
  });

  test(
    'the database refuses a bad shortcut, a duplicate, and a bad app row',
    () {
      SqliteHistoryStore.open(path: path, keyHex: _key).close();
      final db = raw();
      void insert(String? shortcut) => db.execute(
        'INSERT INTO snippets (name, content, type, position, created_at, '
        'updated_at, shortcut) VALUES (?, ?, ?, 0, 1, 1, ?)',
        ['n', 'c', 'other', shortcut],
      );
      insert(null);
      insert(null); // many snippets may have none
      insert(';email');
      for (final bad in [
        'e',
        ';' * 33,
        '; e',
        ';e\t',
        ';e\n',
        ';e\r',
        ';email', // unique
      ]) {
        expect(() => insert(bad), throwsA(isA<SqliteException>()), reason: bad);
      }
      for (final bad in [
        ('', 'Name', 0),
        ('x' * 256, 'Name', 0),
        ('a.b', '', 0),
        ('a.b', 'n' * 101, 0),
        ('a.b', 'Name', 2),
        ('com.1password.1password', 'Again', 0), // unique
      ]) {
        expect(
          () => db.execute(
            'INSERT INTO ignored_apps (app_id, display_name, preset) '
            'VALUES (?, ?, ?)',
            [bad.$1, bad.$2, bad.$3],
          ),
          throwsA(isA<SqliteException>()),
          reason: '$bad',
        );
      }
      db.close();
    },
  );

  test('v3 to v4 keeps every history item, snippet, order and setting', () {
    final v3 = SqliteHistoryStore.open(
      path: path,
      keyHex: _key,
      migrations: kMigrations.sublist(0, 3),
    );
    v3.insertOrBump('first', ClipKind.text, 10);
    v3.insertOrBump('https://example.com', ClipKind.link, 20);
    v3.setLimit(50);
    v3.writeSetting('paste_mode', 'copy');
    final historyBefore = v3.list();
    v3.close();
    // Snippets as a version 3 build wrote them (no shortcut column yet).
    final db = raw();
    db.execute(
      'INSERT INTO snippets (name, content, type, position, created_at, '
      'updated_at) VALUES '
      "('Work email', 'will@example.com', 'email', 1, 30, 30), "
      "('My mobile', '07700 900123', 'phone', 0, 40, 40)",
    );
    db.close();
    final snippetsBefore = [
      (2, 'My mobile', SnippetType.phone, 0, '07700 900123'),
      (1, 'Work email', SnippetType.email, 1, 'will@example.com'),
    ];

    final v4 = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(v4.limit, 50);
    expect(v4.readSetting('paste_mode'), 'copy');
    expect(v4.readSetting('typed_shortcuts_on'), '0');
    expect(
      [for (final i in v4.list()) (i.id, i.preview, i.kind, i.lastCopiedAt)],
      [
        for (final i in historyBefore)
          (i.id, i.preview, i.kind, i.lastCopiedAt),
      ],
    );
    final after = v4.snippetStore().list();
    expect([
      for (final s in after) (s.id, s.name, s.type, s.position, s.preview),
    ], snippetsBefore);
    // Every existing snippet gets no shortcut.
    expect(after.map((s) => s.shortcut), everyElement(isNull));
    expect(
      v4.ignoredAppStore().list().map((a) => a.appId),
      presetIgnoredApps.map((a) => a.appId),
    );
    v4.close();
    // The backup is removed after a successful migration.
    expect(File('$path.bak').existsSync(), isFalse);
  });

  test('the typed_shortcuts_on setting can be read and written', () {
    final store = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(store.readSetting('typed_shortcuts_on'), '0');
    store.writeSetting('typed_shortcuts_on', '1');
    expect(store.readSetting('typed_shortcuts_on'), '1');
    store.close();
  });
}
