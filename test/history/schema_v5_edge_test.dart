// M1.6 tester: more schema version 5 edges (design note "Data", "Rollback")
// and the pause setting in the real encrypted store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:sqlite3/sqlite3.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_v5e_');
    path = '${dir.path}/kusunga.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  SqliteHistoryStore openV4() => SqliteHistoryStore.open(
    path: path,
    keyHex: _key,
    migrations: kMigrations.sublist(0, 4),
  );

  List<String> ids() {
    final db = sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");
    try {
      return [
        for (final r in db.select(
          'SELECT app_id FROM ignored_apps ORDER BY id',
        ))
          r['app_id'] as String,
      ];
    } finally {
      db.close();
    }
  }

  test('v4 with every row removed: only the v5 presets appear, none of the '
      'v4 ones come back', () {
    final v4 = openV4();
    for (final p in presetIgnoredAppsV4) {
      v4.ignoredAppStore().remove(p.appId);
    }
    v4.close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    expect(ids(), [for (final p in presetIgnoredAppsV5) p.appId]);
  });

  test('user rows whose id differs from a preset only in case are not '
      'merged with it', () {
    final first = presetIgnoredAppsV5.firstWhere(
      (p) => appIdIsForWindows(p.appId),
    );
    final v4 = openV4();
    v4.ignoredAppStore().add(
      IgnoredApp(first.appId.toUpperCase(), 'Upper', preset: false),
    );
    v4.close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final all = ids();
    expect(all, contains(first.appId.toUpperCase()));
    expect(all, contains(first.appId));
  });

  test('migrating twice (reopen) adds nothing and keeps the latest '
      'user_version', () {
    openV4().close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final once = ids();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    expect(ids(), once);
    final db = sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");
    expect(
      db.select('PRAGMA user_version').single.values.single,
      kMigrations.last.version,
    );
    db.close();
  });

  test('rollback: a build that only knows version 4 refuses the file and '
      'changes nothing in it', () {
    final v4 = openV4();
    v4.insertOrBump('kept', ClipKind.text, 10);
    v4.close();
    SqliteHistoryStore.open(path: path, keyHex: _key).close();
    final before = ids();
    expect(
      () => SqliteHistoryStore.open(
        path: path,
        keyHex: _key,
        migrations: kMigrations.sublist(0, 4),
      ),
      throwsA(isA<UnsupportedSchemaVersion>()),
    );
    expect(ids(), before);
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(s.list().single.preview, 'kept');
    s.close();
  });

  test('a v4 file that already holds a stored pause key is untouched', () {
    // A tampered or future setting row survives the migration.
    final v4 = openV4();
    v4.close();
    final db = sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");
    db.execute(
      "INSERT INTO settings (key, value) VALUES ('history_paused_until', -1)",
    );
    db.close();
    final s = SqliteHistoryStore.open(path: path, keyHex: _key);
    expect(s.readSetting(historyPausedSetting), '-1');
    s.close();
  });

  group('history_paused_until in the encrypted store', () {
    test('every shape survives close and reopen', () {
      for (final v in ['0', '-1', '1762790400000', '9223372036854775807']) {
        final s = SqliteHistoryStore.open(path: path, keyHex: _key);
        s.writeSetting(historyPausedSetting, v);
        s.close();
        final r = SqliteHistoryStore.open(path: path, keyHex: _key);
        expect(r.readSetting(historyPausedSetting), v);
        r.close();
      }
    });

    test('a value over the length limit is refused, and the old one stays', () {
      final s = SqliteHistoryStore.open(path: path, keyHex: _key);
      s.writeSetting(historyPausedSetting, '-1');
      expect(
        () => s.writeSetting(historyPausedSetting, '1' * 65),
        throwsA(anything),
      );
      expect(s.readSetting(historyPausedSetting), '-1');
      s.close();
    });

    test('an unlisted key is still refused (the list gained one key only)', () {
      final s = SqliteHistoryStore.open(path: path, keyHex: _key);
      expect(() => s.writeSetting('history_paused', '1'), throwsA(anything));
      expect(() => s.readSetting('history_paused_until '), throwsA(anything));
      s.close();
    });
  });
}
