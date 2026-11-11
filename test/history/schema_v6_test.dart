// Schema version 6 (M1.7, docs/design/settings-and-expiry.md "Data", PM
// decision D3 B): expand only. It adds the `history_expiry_days` setting with
// INSERT OR IGNORE: 30 days for a new file, 0 (Never) for a file that already
// holds a version 5 history, so an upgrade never deletes anyone's history.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:sqlite3/sqlite3.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_v6_');
    path = '${dir.path}/kusunga.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Database raw() => sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");

  Object? expiryRow() {
    final db = raw();
    try {
      final rows = db.select(
        "SELECT value FROM settings WHERE key = 'history_expiry_days'",
      );
      return rows.isEmpty ? null : rows.single['value'];
    } finally {
      db.close();
    }
  }

  int userVersion() {
    final db = raw();
    try {
      return db.select('PRAGMA user_version').single.values.single as int;
    } finally {
      db.close();
    }
  }

  SqliteHistoryStore openV5() => SqliteHistoryStore.open(
    path: path,
    keyHex: _key,
    migrations: kMigrations.sublist(0, 5),
  );

  test('the latest version is 6; it only inserts the setting, with INSERT OR '
      'IGNORE, 0 on upgrade and 30 on a new file', () {
    expect(kMigrations.last.version, 6);
    final v6 = kMigrations.last;
    expect(v6.statements, [
      "INSERT OR IGNORE INTO settings (key, value) "
          "VALUES ('history_expiry_days', 0)",
    ]);
    expect(v6.freshStatements, [
      "INSERT OR IGNORE INTO settings (key, value) "
          "VALUES ('history_expiry_days', 30)",
    ]);
  });

  test('a new file starts at 30 days (D3 B)', () {
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(s.readSetting(historyExpirySetting), '30');
    s.close();
    expect(expiryRow(), 30);
    expect(userVersion(), 6);
  });

  test('a v5 file with history is upgraded to Never (0), and nothing in it '
      'is deleted', () {
    final v5 = openV5();
    v5.insertOrBump('very old', ClipKind.text, 1);
    v5.insertOrBump('kept', ClipKind.text, 10);
    v5.snippetStore().insert(
      name: 'Phone',
      content: '0123',
      type: SnippetType.phone,
      nowMs: 5,
    );
    v5.close();
    expect(expiryRow(), isNull);

    final v6 = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(v6.readSetting(historyExpirySetting), '0');
    expect(v6.list().map((i) => i.preview), ['kept', 'very old']);
    expect(v6.snippetStore().list(), hasLength(1));
    v6.close();
    expect(userVersion(), 6);
  });

  test('an empty v5 file is still an upgrade: Never (0)', () {
    openV5().close();
    final v6 = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(v6.readSetting(historyExpirySetting), '0');
    v6.close();
  });

  test('reopening changes nothing: a value the user chose is kept', () {
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    s.writeSetting(historyExpirySetting, '7');
    s.close();
    final again = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(again.readSetting(historyExpirySetting), '7');
    again.close();
    expect(userVersion(), 6);
  });

  test('a row already there (written by hand) is not replaced', () {
    final v5 = openV5();
    v5.close();
    final db = raw();
    db.execute(
      "INSERT INTO settings (key, value) VALUES ('history_expiry_days', 1)",
    );
    db.close();
    final v6 = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(v6.readSetting(historyExpirySetting), '1');
    v6.close();
  });

  test('rollback: a v5 build refuses the v6 file and changes nothing', () {
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    expect(
      openV5,
      throwsA(
        isA<UnsupportedSchemaVersion>().having((e) => e.found, 'found', 6),
      ),
    );
    expect(expiryRow(), 30);
    expect(userVersion(), 6);
  });

  test('the key is a stored setting', () {
    expect(HistoryStore.storedSettingKeys, contains(historyExpirySetting));
  });

  test('memory only: Never (0); nothing in it outlives the session', () {
    final m = MemoryHistoryStore();
    expect(m.readSetting(historyExpirySetting), '0');
  });

  test('auto-delete never touches snippets (R2)', () {
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    s.snippetStore().insert(
      name: 'Old snippet',
      content: 'kept',
      type: SnippetType.other,
      nowMs: 1,
    );
    s.insertOrBump('old copy', ClipKind.text, 1);
    expect(s.deleteOlderThan(1 << 50), 1);
    expect(s.setExpiryDays(1, deleteBefore: 1 << 50), 0);
    expect(s.snippetStore().list().single.name, 'Old snippet');
    s.close();
  });
}
