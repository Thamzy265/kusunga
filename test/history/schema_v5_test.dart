// Schema version 5 (M1.6, docs/design/sensitive-content.md "Data", decision
// D2 A): expand only. It adds the newly verified password-manager presets
// with INSERT OR IGNORE, so a preset the user removed stays removed and an
// app the user added themselves keeps its row. Nothing else changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:sqlite3/sqlite3.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_v5_');
    path = '${dir.path}/kusunga.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Database raw() => sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");

  List<(Object?, Object?, Object?)> rows() {
    final db = raw();
    try {
      return [
        for (final r in db.select(
          'SELECT app_id, display_name, preset FROM ignored_apps ORDER BY id',
        ))
          (r['app_id'], r['display_name'], r['preset']),
      ];
    } finally {
      db.close();
    }
  }

  SqliteHistoryStore openV4() => SqliteHistoryStore.open(
    path: path,
    keyHex: _key,
    migrations: kMigrations.sublist(0, 4),
  );

  test('the latest version is 5, and it only inserts preset rows', () {
    expect(kMigrations.last.version, 5);
    final v5 = kMigrations.last;
    expect(v5.statements, hasLength(1));
    expect(
      v5.statements.single,
      startsWith('INSERT OR IGNORE INTO ignored_apps'),
    );
  });

  test('the full preset list is the v4 list then the v5 list', () {
    expect(presetIgnoredApps, [...presetIgnoredAppsV4, ...presetIgnoredAppsV5]);
    expect(presetIgnoredAppsV5, isNotEmpty);
    for (final p in presetIgnoredAppsV5) {
      expect(p.preset, isTrue, reason: p.appId);
      if (appIdIsForWindows(p.appId)) {
        expect(p.appId, p.appId.toLowerCase(), reason: p.appId);
      }
      expect(
        presetIgnoredAppsV4.any((v4) => v4.appId == p.appId),
        isFalse,
        reason: 'only ids that were never presets before: ${p.appId}',
      );
    }
  });

  test('a new file has every preset, in order, all marked preset', () {
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    expect(rows(), [
      for (final p in presetIgnoredApps) (p.appId, p.displayName, 1),
    ]);
  });

  test('v4 to v5 adds the new presets after the rows that are there', () {
    final v4 = openV4();
    v4.insertOrBump('kept', ClipKind.text, 10);
    v4.writeSetting('typed_shortcuts_on', '1');
    v4.ignoredAppStore().add(const IgnoredApp('com.example.mine', 'Mine'));
    v4.close();

    final v5 = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(v5.list().single.preview, 'kept');
    expect(v5.readSetting('typed_shortcuts_on'), '1');
    v5.close();
    expect(rows(), [
      for (final p in presetIgnoredAppsV4) (p.appId, p.displayName, 1),
      ('com.example.mine', 'Mine', 0),
      for (final p in presetIgnoredAppsV5) (p.appId, p.displayName, 1),
    ]);
  });

  test('a v4 preset the user removed stays removed', () {
    final v4 = openV4();
    v4.ignoredAppStore().remove('com.bitwarden.desktop');
    v4.close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    expect(rows().map((r) => r.$1), isNot(contains('com.bitwarden.desktop')));
  });

  test('an app the user had already added keeps its own row', () {
    final first = presetIgnoredAppsV5.first;
    final v4 = openV4();
    v4.ignoredAppStore().add(IgnoredApp(first.appId, 'My vault'));
    v4.close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final mine = rows().where((r) => r.$1 == first.appId).toList();
    expect(mine, [(first.appId, 'My vault', 0)]);
  });

  test('a v5 preset removed after the upgrade stays removed on reopen', () {
    final id = presetIgnoredAppsV5.first.appId;
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    s.ignoredAppStore().remove(id);
    s.close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    expect(rows().map((r) => r.$1), isNot(contains(id)));
  });

  test('Restore preset list puts the v5 presets back too', () {
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    final store = s.ignoredAppStore();
    for (final p in presetIgnoredAppsV5) {
      store.remove(p.appId);
    }
    store.restorePresets();
    s.close();
    expect(
      rows().map((r) => r.$1).toSet(),
      containsAll(presetIgnoredAppsV5.map((p) => p.appId)),
    );
  });

  test('the v5 literal rows are exactly presetIgnoredAppsV5', () {
    final db = sqlite3.openInMemory();
    db.execute(
      'CREATE TABLE ignored_apps (id INTEGER PRIMARY KEY, app_id TEXT '
      'NOT NULL UNIQUE, display_name TEXT NOT NULL, preset INTEGER NOT NULL)',
    );
    kMigrations.last.statements.forEach(db.execute);
    expect(
      [
        for (final r in db.select(
          'SELECT app_id, display_name, preset FROM ignored_apps ORDER BY id',
        ))
          (r['app_id'], r['display_name'], r['preset']),
      ],
      [for (final p in presetIgnoredAppsV5) (p.appId, p.displayName, 1)],
    );
    db.close();
  });
}
