// M1.10a (tester), AC "existing history and snippets open unchanged".
//
// The strongest automated check that fits in a test run: the schema below is
// FROZEN here as literal SQL copied from the shipped migrations (versions 1
// to 6, as written on Flutter 3.44.6 / sqlite3 3.5.2), not built from
// `kMigrations`. A file is made with the plain sqlite3 package (ChaCha20
// through `hexkey`, the way the store opens it) and filled with SYNTHETIC
// rows, closed, and then opened by the current store.
//
// M1.10b (sqlite3 3.5.2 -> 3.9.2, SQLite3 Multiple Ciphers 2.5.0 -> 2.7.0):
// the files made above are written by whatever library the test runs on, so
// they cannot show that a file written by the OLD library opens on the new
// one. The group "files written by SQLite3 Multiple Ciphers 2.5.0" does: it
// opens two files kept in test/data/fixtures, made once by `_create` (the
// same schema and rows) on sqlite3 3.5.2 / SQLite3 Multiple Ciphers 2.5.0 /
// SQLite 3.53.4, at commit e972d51, with Flutter 3.50.1. Their SHA-256 is
// pinned so they cannot be re-made on a newer library by mistake. It still
// does not prove that a file written by the app binary opens (QA opens the
// real qa profile).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:sqlite3/sqlite3.dart';

// A made-up key, not any real one.
const _key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

const _v1 = [
  '''
CREATE TABLE clip_items (
  id INTEGER PRIMARY KEY,
  content TEXT NOT NULL CHECK (length(CAST(content AS BLOB)) BETWEEN 1 AND 1048576),
  kind TEXT NOT NULL CHECK (kind IN ('text', 'link')),
  content_hash BLOB NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_copied_at INTEGER NOT NULL
)''',
  'CREATE INDEX idx_clip_items_last_copied_at ON clip_items (last_copied_at DESC)',
  '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value INTEGER NOT NULL,
  CHECK (key != 'history_limit' OR value BETWEEN 10 AND 5000)
)''',
];

const _v3 = [
  '''
CREATE TABLE snippets (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  content TEXT NOT NULL CHECK (length(CAST(content AS BLOB)) BETWEEN 1 AND 1048576),
  type TEXT NOT NULL CHECK (type IN ('phone', 'email', 'link', 'address', 'other')),
  position INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
  'CREATE INDEX idx_snippets_position ON snippets (position)',
];

const _v4 = [
  '''
ALTER TABLE snippets ADD COLUMN shortcut TEXT
  CHECK (shortcut IS NULL OR (length(shortcut) BETWEEN 2 AND 32
         AND instr(shortcut, ' ') = 0 AND instr(shortcut, char(9)) = 0
         AND instr(shortcut, char(10)) = 0 AND instr(shortcut, char(13)) = 0))''',
  'CREATE UNIQUE INDEX idx_snippets_shortcut ON snippets (shortcut) WHERE shortcut IS NOT NULL',
  '''
CREATE TABLE ignored_apps (
  id INTEGER PRIMARY KEY,
  app_id TEXT NOT NULL UNIQUE CHECK (length(app_id) BETWEEN 1 AND 255),
  display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 100),
  preset INTEGER NOT NULL CHECK (preset IN (0, 1))
)''',
];

Uint8List _hash(String s) =>
    Uint8List.fromList(sha256.convert(utf8.encode(s)).bytes);

/// (content, kind, createdAt, lastCopiedAt): synthetic, including non-ASCII
/// text, an emoji, a multi-line text and a long one.
final _clips = <(String, String, int, int)>[
  ('synthetic note one', 'text', 1000, 1000),
  ('https://example.invalid/a?b=c&d=e', 'link', 2000, 5000),
  ('Zażółć gęślą jaźń, 你好, \u{1F600}', 'text', 3000, 3000),
  ('line one\nline two\r\n\ttabbed', 'text', 4000, 4500),
  ('x' * 100000, 'text', 500, 6000),
];

const _snips = <(String, String, String, int, String?)>[
  ('Phone (synthetic)', '+44 7700 900000', 'phone', 0, 'ph1'),
  ('Email (synthetic)', 'someone@example.invalid', 'email', 1, 'em1'),
  ('Bank (synthetic)', 'ACCT 00-00-00 00000000', 'other', 2, null),
  ('Link', 'https://example.invalid/', 'link', 3, 'ln'),
];

Database _create(String path, {required int version}) {
  final db = sqlite3.open(path);
  db.execute("PRAGMA cipher = 'chacha20'");
  db.execute("PRAGMA hexkey = '$_key'");
  for (final s in [..._v1]) {
    db.execute(s);
  }
  db.execute("INSERT INTO settings (key, value) VALUES ('history_limit', 321)");
  db.execute('PRAGMA user_version = 1');
  db.execute('PRAGMA user_version = 2');
  for (final s in _v3) {
    db.execute(s);
  }
  db.execute('PRAGMA user_version = 3');
  if (version >= 4) {
    for (final s in _v4) {
      db.execute(s);
    }
    db.execute(
      'INSERT INTO ignored_apps (app_id, display_name, preset) VALUES '
      "('com.1password.1password', '1Password', 1), "
      "('com.bitwarden.desktop', 'Bitwarden', 1), "
      "('com.example.mine', 'My own app', 0)",
    );
    db.execute(
      "INSERT INTO settings (key, value) VALUES ('typed_shortcuts_on', 1)",
    );
    db.execute('PRAGMA user_version = 4');
  }
  if (version >= 6) {
    db.execute('PRAGMA user_version = 5');
    db.execute(
      "INSERT INTO settings (key, value) VALUES ('history_expiry_days', 7)",
    );
    db.execute('PRAGMA user_version = 6');
  }
  for (final c in _clips) {
    db.execute(
      'INSERT INTO clip_items (content, kind, content_hash, created_at, '
      'last_copied_at) VALUES (?, ?, ?, ?, ?)',
      [c.$1, c.$2, _hash(c.$1), c.$3, c.$4],
    );
  }
  for (final s in _snips) {
    if (version >= 4) {
      db.execute(
        'INSERT INTO snippets (name, content, type, position, created_at, '
        'updated_at, shortcut) VALUES (?, ?, ?, ?, 10, 20, ?)',
        [s.$1, s.$2, s.$3, s.$4, s.$5],
      );
    } else {
      db.execute(
        'INSERT INTO snippets (name, content, type, position, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, 10, 20)',
        [s.$1, s.$2, s.$3, s.$4],
      );
    }
  }
  return db;
}

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_frozen_');
    path = '${dir.path}/kusunga.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a frozen version 6 file opens with every item, snippet and setting '
      'unchanged, and no migration runs', () {
    _create(path, version: 6).close();
    final before = File(path).readAsBytesSync();

    final store = SqliteHistoryStore.open(path: path, keyHex: _key);
    addTearDown(store.close);

    expect(store.limit, 321);
    expect(store.count, _clips.length);
    final items = store.list();
    // Newest first by last_copied_at.
    expect(items.map((i) => i.lastCopiedAt).toList(), [
      6000,
      5000,
      4500,
      3000,
      1000,
    ]);
    expect(items.map((i) => i.createdAt).toList(), [
      500,
      2000,
      4000,
      3000,
      1000,
    ]);
    final byId = {for (final r in store.records()) r.content: r};
    for (final c in _clips) {
      final r = byId[c.$1];
      expect(r, isNotNull, reason: 'lost: ${c.$1.substring(0, 10)}');
      expect(r!.kind.name, c.$2);
      expect(r.createdAt, c.$3);
      expect(r.lastCopiedAt, c.$4);
    }
    expect(store.readSetting('typed_shortcuts_on'), '1');
    expect(store.readSetting('history_expiry_days'), '7');

    final snippets = store.snippetStore();
    final list = snippets.list();
    expect(list.map((s) => s.name), _snips.map((s) => s.$1));
    expect(list.map((s) => s.position), [0, 1, 2, 3]);
    expect(list.map((s) => s.shortcut), ['ph1', 'em1', null, 'ln']);
    expect(list.map((s) => s.type), [
      SnippetType.phone,
      SnippetType.email,
      SnippetType.other,
      SnippetType.link,
    ]);
    for (final s in list) {
      expect(
        snippets.contentOf(s.id),
        _snips.firstWhere((x) => x.$1 == s.name).$2,
      );
    }

    // Already at the latest version: the open did not write a backup and
    // did not rewrite the file.
    expect(File('$path.bak').existsSync(), isFalse);
    store.close();
    expect(File(path).readAsBytesSync(), before);
  });

  test('the opened version 6 file still works: copy, bump, trim, a new '
      'snippet, and a re-open sees it', () {
    _create(path, version: 6).close();
    var store = SqliteHistoryStore.open(path: path, keyHex: _key);
    // Same text as an old row: bumped, not duplicated.
    store.insertOrBump('synthetic note one', ClipKind.text, 9000);
    store.insertOrBump('brand new', ClipKind.text, 9500);
    expect(store.count, _clips.length + 1);
    expect(store.list().first.preview, 'brand new');
    expect(store.list()[1].preview, 'synthetic note one');
    store.snippetStore().insert(
      name: 'added',
      content: 'new snippet',
      type: SnippetType.other,
      nowMs: 9600,
    );
    store.close();

    store = SqliteHistoryStore.open(path: path, keyHex: _key);
    addTearDown(store.close);
    expect(store.count, _clips.length + 1);
    expect(store.snippetStore().list(), hasLength(_snips.length + 1));
    expect(store.snippetStore().list().last.position, _snips.length);
  });

  test('a wrong key still fails, and an intact file is not harmed by it', () {
    _create(path, version: 6).close();
    const wrong =
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    expect(
      () => SqliteHistoryStore.open(path: path, keyHex: wrong),
      throwsA(isA<SqliteException>()),
    );
    final store = SqliteHistoryStore.open(path: path, keyHex: _key);
    addTearDown(store.close);
    expect(store.count, _clips.length);
  });

  test('a frozen version 3 file (history and snippets, no shortcuts) '
      'upgrades to the latest schema with all rows kept, auto-delete Never '
      'and no backup left behind', () {
    _create(path, version: 3).close();
    final before = File(path).readAsBytesSync();

    final store = SqliteHistoryStore.open(path: path, keyHex: _key);
    addTearDown(store.close);

    expect(store.count, _clips.length);
    expect(store.limit, 321);
    // An upgrade never deletes anyone's history (PM decision D3 B).
    expect(store.readSetting('history_expiry_days'), '0');
    expect(store.readSetting('typed_shortcuts_on'), '0');
    final list = store.snippetStore().list();
    expect(list.map((s) => s.name), _snips.map((s) => s.$1));
    expect(list.every((s) => s.shortcut == null), isTrue);
    // The backup made for the upgrade is removed once it succeeded.
    expect(File('$path.bak').existsSync(), isFalse);
    expect(File(path).readAsBytesSync(), isNot(before));

    final raw = sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");
    addTearDown(raw.close);
    expect(raw.select('PRAGMA user_version').single.values.single, 6);
    expect(
      raw.select('SELECT count(*) c FROM ignored_apps').single['c'],
      greaterThanOrEqualTo(9),
    );
  });

  test('a user-removed preset stays removed and a user-added ignored app '
      'stays after the open', () {
    _create(path, version: 6).close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final raw = sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");
    addTearDown(raw.close);
    final ids = raw
        .select('SELECT app_id FROM ignored_apps')
        .map((r) => r['app_id'])
        .toSet();
    expect(ids, {
      'com.1password.1password',
      'com.bitwarden.desktop',
      'com.example.mine',
    });
  });

  group('files written by SQLite3 Multiple Ciphers 2.5.0 (sqlite3 3.5.2)', () {
    const v3 = 'test/data/fixtures/frozen_v3_sqlite3mc_2_5_0.db';
    const v6 = 'test/data/fixtures/frozen_v6_sqlite3mc_2_5_0.db';

    /// A copy in the test's temporary folder, so an open never changes the
    /// kept file.
    String copy(String fixture) {
      File(fixture).copySync(path);
      return path;
    }

    test('the kept files are the ones made on 2.5.0, and are encrypted', () {
      for (final (file, hash) in [
        (
          v3,
          '974b81794bf7f72344734f384ed5248bc9cfadb9055a635c20266268d254dcfb',
        ),
        (
          v6,
          '5423421838e41f0e35df93de79832aca4ff706b1448a1445eb4dcc321ab24709',
        ),
      ]) {
        final bytes = File(file).readAsBytesSync();
        expect(sha256.convert(bytes).toString(), hash, reason: file);
        // A plain SQLite file starts with "SQLite format 3"; these do not.
        expect(
          ascii.decode(bytes.sublist(0, 15), allowInvalid: true),
          isNot('SQLite format 3'),
          reason: file,
        );
      }
    });

    test('the version 6 file opens with the existing key, every item, '
        'snippet and setting unchanged, and is not rewritten', () {
      final file = copy(v6);
      final before = File(file).readAsBytesSync();
      final store = SqliteHistoryStore.open(path: file, keyHex: _key);
      addTearDown(store.close);

      expect(store.limit, 321);
      expect(store.count, _clips.length);
      final byContent = {for (final r in store.records()) r.content: r};
      for (final c in _clips) {
        final r = byContent[c.$1];
        expect(r, isNotNull, reason: 'lost: ${c.$1.substring(0, 10)}');
        expect(r!.kind.name, c.$2);
        expect(r.createdAt, c.$3);
        expect(r.lastCopiedAt, c.$4);
      }
      expect(store.readSetting('typed_shortcuts_on'), '1');
      expect(store.readSetting('history_expiry_days'), '7');
      final snippets = store.snippetStore();
      final list = snippets.list();
      expect(list.map((s) => s.name), _snips.map((s) => s.$1));
      expect(list.map((s) => s.shortcut), ['ph1', 'em1', null, 'ln']);
      for (final s in list) {
        expect(
          snippets.contentOf(s.id),
          _snips.firstWhere((x) => x.$1 == s.name).$2,
        );
      }
      expect(File('$file.bak').existsSync(), isFalse);
      store.close();
      expect(File(file).readAsBytesSync(), before);
    });

    test('the version 6 file takes new writes on this library and opens '
        'again with them', () {
      final file = copy(v6);
      var store = SqliteHistoryStore.open(path: file, keyHex: _key);
      store.insertOrBump('written by the new library', ClipKind.text, 9500);
      store.close();
      store = SqliteHistoryStore.open(path: file, keyHex: _key);
      addTearDown(store.close);
      expect(store.count, _clips.length + 1);
      expect(store.list().first.preview, 'written by the new library');
    });

    test('the version 3 file upgrades to the latest schema with all rows '
        'kept', () {
      final file = copy(v3);
      final store = SqliteHistoryStore.open(path: file, keyHex: _key);
      addTearDown(store.close);
      expect(store.count, _clips.length);
      expect(store.limit, 321);
      expect(store.readSetting('history_expiry_days'), '0');
      final list = store.snippetStore().list();
      expect(list.map((s) => s.name), _snips.map((s) => s.$1));
      expect(list.every((s) => s.shortcut == null), isTrue);
      expect(File('$file.bak').existsSync(), isFalse);
      store.close();
      final raw = sqlite3.open(file)..execute("PRAGMA hexkey = '$_key'");
      addTearDown(raw.close);
      expect(raw.select('PRAGMA user_version').single.values.single, 6);
    });

    test('a wrong key fails on both files and leaves them unchanged', () {
      const wrong =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      for (final fixture in [v3, v6]) {
        final file = copy(fixture);
        final before = File(file).readAsBytesSync();
        expect(
          () => SqliteHistoryStore.open(path: file, keyHex: wrong),
          throwsA(isA<SqliteException>()),
          reason: fixture,
        );
        expect(File(file).readAsBytesSync(), before, reason: fixture);
        expect(File('$file.bak').existsSync(), isFalse, reason: fixture);
      }
    });
  });
}
