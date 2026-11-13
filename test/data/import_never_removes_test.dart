// M1.8 tester, re-check of R1 (PM decision 2026-11-13, "Never remove"): an
// import never deletes history, imported history fills only the free room
// under the limit (newest first), and a limit or auto-delete time that would
// delete a shown item is kept. Real encrypted SQLite files in temp folders.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/expiry_service.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _now = 1700000000000;
const _day = Duration.millisecondsPerDay;
const _min = 60000;

ExportHistoryItem _h(String content, int last, {int? created}) =>
    ExportHistoryItem(
      content: content,
      kind: ClipKind.text,
      createdAt: created ?? last,
      lastCopiedAt: last,
    );

typedef Row = ({int id, String content, int created, int last});

void main() {
  late Directory dir;
  late String path;
  late SqliteHistoryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_r1_');
    path = '${dir.path}/kusunga.db';
    store = SqliteHistoryStore.open(path: path, keyHex: _key);
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA hexkey = '$_key'");
    return db;
  }

  void setLimitRaw(int limit) {
    final db = raw();
    db.execute("UPDATE settings SET value = ? WHERE key = 'history_limit'", [
      limit,
    ]);
    db.close();
  }

  /// Exact rows with exact times, written through the import itself with a
  /// limit that leaves room; the limit is then set to [limit].
  void seed(Map<String, int> rows, {int limit = 5000}) {
    setLimitRaw(5000);
    store.importBundle(
      ExportBundle(
        snippets: const [],
        history: [for (final e in rows.entries) _h(e.key, e.value)],
      ),
      applySettings: false,
      nowMs: _now,
    );
    setLimitRaw(limit);
  }

  String? rawSetting(String key) {
    final db = raw();
    try {
      final r = db.select('SELECT value FROM settings WHERE key = ?', [key]);
      return r.isEmpty ? null : '${r.single['value']}';
    } finally {
      db.close();
    }
  }

  List<Row> rows() {
    final db = raw();
    try {
      return [
        for (final r in db.select(
          'SELECT id, content, created_at, last_copied_at FROM clip_items '
          'ORDER BY id',
        ))
          (
            id: r['id'] as int,
            content: r['content'] as String,
            created: r['created_at'] as int,
            last: r['last_copied_at'] as int,
          ),
      ];
    } finally {
      db.close();
    }
  }

  Object settingsDump() {
    final db = raw();
    try {
      return [
        for (final r in db.select('SELECT * FROM settings ORDER BY key'))
          r.values.toList(),
        for (final r in db.select('SELECT * FROM ignored_apps ORDER BY app_id'))
          r.values.toList(),
      ];
    } finally {
      db.close();
    }
  }

  /// No row that was here is gone, and none lost its content.
  void expectNothingRemoved(
    List<Row> before, {
    Set<String> mayChange = const {},
  }) {
    final after = {for (final r in rows()) r.id: r};
    for (final b in before) {
      final a = after[b.id];
      expect(a, isNotNull, reason: 'row ${b.content} was deleted');
      expect(a!.content, b.content);
      if (!mayChange.contains(b.content)) {
        expect(a.last, b.last, reason: '${b.content} last changed');
        expect(a.created, b.created, reason: '${b.content} created changed');
      }
    }
  }

  ImportCounts run(
    ExportBundle b, {
    bool settings = false,
    int? notBefore,
    bool checkPreview = true,
  }) {
    if (checkPreview) {
      final snapshot = '${rows()} ${settingsDump()}';
      final preview = store.previewImport(
        b,
        applySettings: settings,
        notBefore: notBefore,
        nowMs: _now,
      );
      expect(
        '${rows()} ${settingsDump()}',
        snapshot,
        reason: 'preview changed data',
      );
      final real = store.importBundle(
        b,
        applySettings: settings,
        notBefore: notBefore,
        nowMs: _now,
      );
      for (final (name, a, c) in [
        ('historyAdded', preview.historyAdded, real.historyAdded),
        ('historyTooOld', preview.historyTooOld, real.historyTooOld),
        (
          'historyAlreadyHere',
          preview.historyAlreadyHere,
          real.historyAlreadyHere,
        ),
        (
          'snippetsAlreadyHere',
          preview.snippetsAlreadyHere,
          real.snippetsAlreadyHere,
        ),
        ('settingsApplied', preview.settingsApplied, real.settingsApplied),
        ('historyNoRoom', preview.historyNoRoom, real.historyNoRoom),
        ('snippetsAdded', preview.snippetsAdded, real.snippetsAdded),
        ('limitKept', preview.limitKept, real.limitKept),
        ('expiryKept', preview.expiryKept, real.expiryKept),
      ]) {
        expect(a, c, reason: 'preview $name');
      }
      return real;
    }
    return store.importBundle(
      b,
      applySettings: settings,
      notBefore: notBefore,
      nowMs: _now,
    );
  }

  ExportBundle hist(
    List<ExportHistoryItem> h, {
    ExportSettings? settings,
    List<IgnoredApp>? apps,
  }) => ExportBundle(
    snippets: const [],
    history: h,
    settings: settings,
    ignoredApps: apps,
  );

  group('free room under the limit', () {
    test('exactly full: nothing is added, nothing is removed, all are '
        'counted as not fitting', () {
      seed({
        for (var i = 0; i < 10; i++) 'mine $i': _now - i * _min,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([for (var i = 0; i < 7; i++) _h('theirs $i', _now - i)]),
      );
      expect(c.historyAdded, 0);
      expect(c.historyNoRoom, 7);
      expect(rows(), before);
    });

    test('exactly full, but the file also holds texts already shown: those '
        'merge (they need no room), the rest do not fit', () {
      seed({
        for (var i = 0; i < 10; i++) 'mine $i': _now - (i + 1) * _min,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([_h('mine 3', _now), _h('theirs', _now - 1), _h('mine 4', 5)]),
      );
      expect(c.historyAdded, 0);
      expect(c.historyNoRoom, 1);
      expectNothingRemoved(before);
      expect(c.historyAlreadyHere, 2);
      expect(rows().length, 10);
    });

    test('one free place: only the newest line of the file is added', () {
      seed({
        for (var i = 0; i < 9; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([
          _h('old', _now - 50 * _min),
          _h('newest', _now - 1),
          _h('middle', _now - 10 * _min),
        ]),
      );
      expect(c.historyAdded, 1);
      expect(c.historyNoRoom, 2);
      expect(rows().map((r) => r.content), contains('newest'));
      expect(rows().map((r) => r.content), isNot(contains('middle')));
      expectNothingRemoved(before);
    });

    test('a file larger than the free room: the newest fill it, in the '
        'file order on disk; a tie goes to the line that comes first', () {
      seed({
        for (var i = 0; i < 7; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([
          for (var i = 0; i < 12; i++) _h('theirs $i', _now - (i ~/ 2) * _min),
        ]),
      );
      // times: 0,0,1,1,2,2,... minutes ago. Three places: lines 0, 1 (the
      // newest pair) and, on the tie at 1 minute, line 2 before line 3.
      expect(c.historyAdded, 3);
      expect(c.historyNoRoom, 9);
      expect(rows().skip(before.length).map((r) => r.content).toList(), [
        'theirs 0',
        'theirs 1',
        'theirs 2',
      ]);
      expectNothingRemoved(before);
    });

    test('lines that repeat one text need one place, not two', () {
      seed({
        for (var i = 0; i < 8; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 10);
      final c = run(
        hist([
          _h('a', _now - 1),
          _h('a', _now - 5),
          _h('b', _now - 2),
          _h('c', _now - 3),
        ]),
      );
      expect(c.historyAdded, 2);
      expect(c.historyNoRoom, 1);
      final a = rows().firstWhere((r) => r.content == 'a');
      expect(a.last, _now - 1, reason: 'repeated lines merge as Undo does');
    });

    test('more rows than the limit already (hidden ones, or a lowered '
        'limit): the room is 0, never negative, and nothing goes', () {
      seed({
        for (var i = 0; i < 15; i++) 'mine $i': _now - (i + 1) * _min,
      }, limit: 10);
      final before = rows();
      final c = run(hist([_h('x', _now), _h('mine 1', _now)]));
      expect(c.historyAdded, 0);
      expect(c.historyNoRoom, 1);
      expect(rows().length, 15);
      expectNothingRemoved(before);
      expect(c.historyAlreadyHere, 1);
    });

    test('an empty history with the smallest limit: exactly the limit is '
        'added, newest first', () {
      setLimitRaw(10);
      final c = run(
        hist([for (var i = 0; i < 25; i++) _h('t$i', _now - i * _min)]),
      );
      expect(c.historyAdded, 10);
      expect(c.historyNoRoom, 15);
      expect(rows().map((r) => r.content).toSet(), {
        for (var i = 0; i < 10; i++) 't$i',
      });
    });
  });

  group('hidden items (older than auto-delete) versus shown ones', () {
    final cutoff = expiryCutoff(30, _now);

    test('hidden rows take no room; a hidden text that comes back in the '
        'file needs a place and is revived', () {
      seed({
        for (var i = 0; i < 8; i++) 'shown $i': _now - (i + 1) * _day,
        for (var i = 0; i < 6; i++) 'hidden $i': _now - (40 + i) * _day,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([
          _h('hidden 0', _now - _day),
          _h('fresh', _now - 2 * _day),
          _h('fresher', _now),
        ]),
        notBefore: cutoff,
      );
      // two places: the two newest of the three that need room
      expect(c.historyAdded, 2);
      expect(c.historyNoRoom, 1);
      final names = rows().map((r) => r.content).toList();
      expect(names, contains('fresher'));
      expect(names, contains('hidden 0'));
      expect(names, isNot(contains('fresh')));
      expectNothingRemoved(before, mayChange: {'hidden 0'});
    });

    test('no room: a hidden text is not revived and its row is left exactly '
        'as it was', () {
      seed({
        for (var i = 0; i < 10; i++) 'shown $i': _now - (i + 1) * _day,
        'hidden': _now - 40 * _day,
      }, limit: 10);
      final before = rows();
      final c = run(hist([_h('hidden', _now)]), notBefore: cutoff);
      expect(c.historyAdded, 0);
      expect(c.historyNoRoom, 1);
      expect(rows(), before);
    });

    test('a line for a hidden text that is itself too old is "too old", not '
        '"no room"; its row is unchanged', () {
      seed({'hidden': _now - 40 * _day}, limit: 10);
      final before = rows();
      final c = run(hist([_h('hidden', _now - 35 * _day)]), notBefore: cutoff);
      expect(c.historyTooOld, 1);
      expect(c.historyNoRoom, 0);
      expect(rows(), before);
    });

    test('R9: a shown text is left exactly as it is even when the history '
        'is full (already here, no room needed); a hidden twin of another '
        'text needs a place and does not confuse it', () {
      seed({
        for (var i = 0; i < 9; i++) 'shown $i': _now - (i + 1) * _day,
        'last shown': _now - 20 * _day,
        'hidden': _now - 50 * _day,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([
          _h('last shown', _now - 10 * _day),
          _h('hidden', _now - 9 * _day),
        ]),
        notBefore: cutoff,
      );
      expect(c.historyAdded, 0);
      expect(c.historyAlreadyHere, 1);
      expect(c.historyNoRoom, 1, reason: 'only the hidden one needs a place');
      expect(rows(), before, reason: 'no time, no id, no row changed');
    });

    test('R9: a hidden text that comes back with room is revived with the '
        'file\'s times merged; the shown text beside it stays untouched', () {
      seed({
        for (var i = 0; i < 8; i++) 'shown $i': _now - (i + 1) * _day,
        'hidden': _now - 50 * _day,
      }, limit: 10);
      final before = rows();
      final c = run(
        hist([
          _h('shown 3', _now, created: _now - 90 * _day),
          _h('hidden', _now - 9 * _day, created: _now - 60 * _day),
        ]),
        notBefore: cutoff,
      );
      expect(c.historyAdded, 1);
      expect(c.historyAlreadyHere, 1);
      final after = {for (final r in rows()) r.content: r};
      final was = {for (final r in before) r.content: r};
      expect(after['shown 3'], was['shown 3']);
      expect(after['hidden']!.id, was['hidden']!.id, reason: 'same row');
      expect(after['hidden']!.last, _now - 9 * _day);
      expect(after['hidden']!.created, _now - 60 * _day);
    });

    test('R9: repeated lines of a shown text count once; a line older than '
        'the auto-delete time is "too old", not "already here"', () {
      seed({'shown': _now - 2 * _day}, limit: 10);
      final before = rows();
      final c = run(
        hist([
          _h('shown', _now),
          _h('shown', _now - _day),
          _h('shown', _now - 40 * _day),
        ]),
        notBefore: cutoff,
      );
      expect(c.historyAlreadyHere, 1);
      expect(c.historyTooOld, 1);
      expect(rows(), before);
    });

    test('R9: with no auto-delete time every existing text is shown, so '
        'every matching line is already here', () {
      seed({'old': _now - 400 * _day, 'new': _now - _day}, limit: 10);
      final before = rows();
      final c = run(hist([_h('old', _now), _h('new', 1), _h('fresh', _now)]));
      expect(c.historyAlreadyHere, 2);
      expect(c.historyAdded, 1);
      expect(rows().where((r) => r.content != 'fresh').toList(), before);
    });
  });

  group('the file\'s settings: kept or applied, with and without the tick', () {
    test('not ticked: no setting, no app, and the room comes from today\'s '
        'limit', () {
      seed({
        for (var i = 0; i < 5; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 10);
      final before = settingsDump();
      final c = run(
        hist(
          [for (var i = 0; i < 6; i++) _h('t$i', _now - i * _min)],
          settings: const ExportSettings(
            historyLimit: 5000,
            historyExpiryDays: 7,
            typedShortcutsOn: true,
            pasteMode: 'copy_only',
          ),
          apps: const [IgnoredApp('com.vault', 'Vault')],
        ),
      );
      expect(c.historyAdded, 5, reason: 'room 10 - 5 shown');
      expect(c.limitKept, isFalse);
      expect(settingsDump(), before);
    });

    test('a lower limit than the shown items is kept; every other setting '
        'and the apps still apply', () {
      seed({
        for (var i = 0; i < 20; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 50);
      final before = rows();
      final c = run(
        hist(
          [_h('t', _now)],
          settings: const ExportSettings(
            historyLimit: 10,
            typedShortcutsOn: true,
            pasteMode: 'copy_only',
          ),
          apps: const [IgnoredApp('com.vault', 'Vault')],
        ),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.limitKept, isTrue);
      expect(c.expiryKept, isFalse);
      expect(c.historyAdded, 1, reason: 'the old limit of 50 gives room');
      expect(rawSetting('history_limit'), '50');
      expect(rawSetting('typed_shortcuts_on'), '1');
      expect(rawSetting('paste_mode'), 'copy_only');
      expect(
        store.ignoredAppStore().list().map((a) => a.appId),
        contains('com.vault'),
      );
      expectNothingRemoved(before);
      expect(
        store.limit,
        50,
        reason: 'the cached limit follows what was saved',
      );
    });

    test('a limit equal to the shown items is applied, and then there is no '
        'room', () {
      seed({
        for (var i = 0; i < 12; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 50);
      final c = run(
        hist([_h('t', _now)], settings: const ExportSettings(historyLimit: 12)),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.limitKept, isFalse);
      expect(rawSetting('history_limit'), '12');
      expect(c.historyAdded, 0);
      expect(c.historyNoRoom, 1);
      expect(store.limit, 12);
    });

    test('a limit one under the shown items is kept', () {
      seed({
        for (var i = 0; i < 12; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 50);
      final c = run(
        hist([], settings: const ExportSettings(historyLimit: 11)),
        settings: true,
      );
      expect(c.limitKept, isTrue);
      expect(rawSetting('history_limit'), '50');
    });

    test('hidden rows do not count against a new limit', () {
      seed({
        for (var i = 0; i < 5; i++) 'shown $i': _now - (i + 1) * _day,
        for (var i = 0; i < 20; i++) 'hidden $i': _now - (40 + i) * _day,
      }, limit: 50);
      final before = rows();
      final c = run(
        hist([], settings: const ExportSettings(historyLimit: 10)),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.limitKept, isFalse);
      expect(rawSetting('history_limit'), '10');
      expect(rows(), before, reason: 'the store never deletes in an import');
    });

    test('a shorter auto-delete that would hide a shown item is kept, and '
        'items between the two times are judged by the time in use', () {
      seed({
        'two days': _now - 2 * _day,
        'ten days': _now - 10 * _day,
      }, limit: 50);
      final before = rows();
      final c = run(
        hist([
          _h('three days', _now - 3 * _day),
          _h('thirty-five', _now - 35 * _day),
        ], settings: const ExportSettings(historyExpiryDays: 1)),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.expiryKept, isTrue);
      expect(rawSetting('history_expiry_days') ?? '0', isNot('1'));
      expect(c.historyAdded, 1, reason: '"three days" is under the 30 in use');
      expect(c.historyTooOld, 1);
      expectNothingRemoved(before);
    });

    test('a shorter auto-delete that would hide only what is hidden '
        'already is applied, and its time then decides "too old"', () {
      seed({
        'two days': _now - 2 * _day,
        'forty days': _now - 40 * _day,
      }, limit: 50);
      final c = run(
        hist([
          _h('five days', _now - 5 * _day),
          _h('three days', _now - 3 * _day),
        ], settings: const ExportSettings(historyExpiryDays: 7)),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.expiryKept, isFalse);
      expect(rawSetting('history_expiry_days'), '7');
      expect(c.historyAdded, 2);
      // 7 days would delete nothing shown here ("two days" is newer), but
      // a 1-day cut-off would hide the line:
      final c2 = run(
        hist([
          _h('one and a half', _now - 36 * 60 * _min),
        ], settings: const ExportSettings(historyExpiryDays: 1)),
        settings: true,
        notBefore: expiryCutoff(7, _now),
      );
      expect(c2.expiryKept, isTrue, reason: '"two days" is shown and would go');
    });

    test('Never (0 days) is always applied, and the rows it brings back '
        'into view count against a new limit', () {
      seed({
        for (var i = 0; i < 8; i++) 'shown $i': _now - (i + 1) * _day,
        for (var i = 0; i < 5; i++) 'hidden $i': _now - (40 + i) * _day,
      }, limit: 50);
      final c = run(
        hist(
          [],
          settings: const ExportSettings(
            historyExpiryDays: 0,
            historyLimit: 10,
          ),
        ),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.expiryKept, isFalse);
      expect(c.limitKept, isTrue, reason: '13 items would then be shown');
      expect(rawSetting('history_expiry_days'), '0');
    });

    test('both kept: both flags, the old values stay, the rest applies', () {
      seed({
        for (var i = 0; i < 20; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 50);
      final c = run(
        hist(
          [],
          settings: const ExportSettings(
            historyLimit: 10,
            historyExpiryDays: 1,
            pasteMode: 'copy_only',
          ),
        ),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c.limitKept && c.expiryKept, isTrue);
      expect(rawSetting('paste_mode'), 'copy_only');
      expect(rawSetting('history_limit'), '50');
    });

    test('a file with no history but a lower limit: kept, nothing added or '
        'removed', () {
      seed({
        for (var i = 0; i < 20; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 50);
      final before = rows();
      final c = run(
        hist([], settings: const ExportSettings(historyLimit: 10)),
        settings: true,
      );
      expect(c.limitKept, isTrue);
      expect(c.historyAdded, 0);
      expect(rows(), before);
    });

    test('a higher limit is applied and gives room at once in the same '
        'import', () {
      seed({
        for (var i = 0; i < 10; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 10);
      final c = run(
        hist([
          for (var i = 0; i < 20; i++) _h('t$i', _now - i * _min),
        ], settings: const ExportSettings(historyLimit: 15)),
        settings: true,
      );
      expect(c.limitKept, isFalse);
      expect(c.historyAdded, 5);
      expect(c.historyNoRoom, 15);
    });
  });

  group('the preview equals the import in a sweep, and no row is ever '
      'removed', () {
    // A fixed mix of existing rows and file lines, every limit and both
    // ticks, with and without an auto-delete cut-off.
    for (final limit in [10, 12, 13, 14, 20, 50]) {
      for (final apply in [false, true]) {
        for (final withCutoff in [false, true]) {
          test('limit $limit, settings ${apply ? 'ticked' : 'not'}, '
              '${withCutoff ? '30 days' : 'never'}', () {
            seed({
              for (var i = 0; i < 9; i++) 'shown $i': _now - (i + 1) * _day,
              for (var i = 0; i < 4; i++) 'hidden $i': _now - (40 + i) * _day,
            }, limit: limit < 13 ? 13 : limit);
            setLimitRaw(limit < 9 ? 9 : limit);
            final before = rows();
            run(
              hist(
                [
                  for (var i = 0; i < 15; i++) _h('t$i', _now - i * _min),
                  _h('shown 2', _now),
                  _h('hidden 1', _now - _day),
                  _h('hidden 2', _now - 50 * _day),
                  _h('t3', _now - 2 * _min), // a repeat
                ],
                settings: ExportSettings(
                  historyLimit: limit,
                  historyExpiryDays: 7,
                ),
              ),
              settings: apply,
              notBefore: withCutoff ? expiryCutoff(30, _now) : null,
            );
            expectNothingRemoved(
              before,
              mayChange: withCutoff ? {'hidden 1'} : {},
            );
          });
        }
      }
    }
  });

  group('the service: paused, and what the list and settings show after', () {
    late HistoryService service;
    late FakeClipboardSource source;

    setUp(() {
      source = FakeClipboardSource();
      service = HistoryService(
        store: store,
        source: source,
        log: FakeLog(),
        clock: () => _now,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
    });
    tearDown(() async {
      await service.close();
      service.dispose();
    });

    test('while paused the imported history still fills the free room, and '
        'the preview says the same number', () async {
      seed({
        for (var i = 0; i < 6; i++) 'mine $i': _now - (i + 1) * _day,
      }, limit: 10);
      service.snippets.reload();
      expect(await service.pause.pause(PauseLength.untilResumed), isTrue);
      final bundle = hist([
        for (var i = 0; i < 9; i++) _h('t$i', _now - i * _min),
      ]);
      final preview = service.historyToAdd(bundle, applySettings: false);
      final c = service.importBundle(bundle, applySettings: false);
      expect(preview, 4);
      expect(c.historyAdded, 4);
      expect(c.historyNoRoom, 5);
      expect(service.pause.isPaused, isTrue);
    });

    test('a ticked file leaves no shown item deleted by the clean-up that '
        'follows: items before and after the import, apart from the ones '
        'that were already hidden', () {
      seed({
        for (var i = 0; i < 6; i++) 'shown $i': _now - (i + 1) * _day,
        for (var i = 0; i < 3; i++) 'hidden $i': _now - (40 + i) * _day,
      }, limit: 10);
      service.expiry.setDays(30);
      final shownBefore = service.items.map((i) => i.preview).toSet();
      expect(shownBefore, hasLength(6));
      service.importBundle(
        hist(
          [_h('t', _now)],
          settings: const ExportSettings(
            historyLimit: 10,
            historyExpiryDays: 1,
          ),
        ),
        applySettings: true,
      );
      final after = service.items.map((i) => i.preview).toSet();
      expect(
        after.containsAll(shownBefore),
        isTrue,
        reason: 'a shorter auto-delete would have deleted shown items',
      );
      expect(service.expiry.days, 30);
    });
  });

  group('R9 (was BUG-R9): merges into shown items change nothing', () {
    test('importing a text that is already shown leaves its row exactly as '
        'it was, so "nothing you have now will be changed" is true', () {
      seed({'mine': _now - 5 * _day});
      final before = rows();
      run(hist([_h('mine', _now - _day)]));
      expect(rows(), before);
    });
  });
  group('R10: settingsApplied is true only when something really changed', () {
    ExportSettings current() => ExportSettings(
      historyLimit: int.parse(rawSetting('history_limit')!),
      historyExpiryDays: int.parse(rawSetting('history_expiry_days')!),
      typedShortcutsOn: rawSetting('typed_shortcuts_on') == '1',
    );

    ExportBundle only({ExportSettings? settings, List<IgnoredApp>? apps}) =>
        ExportBundle(snippets: const [], settings: settings, ignoredApps: apps);

    test(
      'values already in use: nothing changed, and no setting row moves',
      () {
        final before = settingsDump();
        final c = run(only(settings: current()), settings: true);
        expect(c.settingsApplied, isFalse);
        expect(settingsDump(), before);
      },
    );

    test('not ticked: never applied, even with different values', () {
      final c = run(
        only(settings: const ExportSettings(pasteMode: 'copy_only')),
      );
      expect(c.settingsApplied, isFalse);
    });

    test('one value that differs: applied; each setting alone counts', () {
      for (final (s, key, value) in <(ExportSettings, String, String)>[
        (const ExportSettings(historyLimit: 77), 'history_limit', '77'),
        (
          const ExportSettings(historyExpiryDays: 7),
          'history_expiry_days',
          '7',
        ),
        (
          const ExportSettings(typedShortcutsOn: true),
          'typed_shortcuts_on',
          '1',
        ),
        (
          const ExportSettings(pasteMode: 'copy_only'),
          'paste_mode',
          'copy_only',
        ),
      ]) {
        final c = run(only(settings: s), settings: true);
        expect(c.settingsApplied, isTrue, reason: key);
        expect(rawSetting(key), value);
        // the same file again: already in use now
        final again = run(only(settings: s), settings: true);
        expect(again.settingsApplied, isFalse, reason: 'second $key');
      }
    });

    test('a kept value alone is not a change', () {
      seed({for (var i = 0; i < 20; i++) 'mine $i': _now - (i + 1) * _day});
      final c = run(
        only(settings: const ExportSettings(historyLimit: 10)),
        settings: true,
      );
      expect(c.limitKept, isTrue);
      expect(c.settingsApplied, isFalse);
      seed({}); // no-op: keeps the helper symmetrical
      final c2 = run(
        only(settings: const ExportSettings(historyExpiryDays: 1)),
        settings: true,
        notBefore: expiryCutoff(30, _now),
      );
      expect(c2.expiryKept, isTrue);
      expect(c2.settingsApplied, isFalse);
    });

    test('a mix: a kept limit with a changed paste mode is applied; a kept '
        'limit with a paste mode already in use is not', () {
      seed({for (var i = 0; i < 20; i++) 'mine $i': _now - (i + 1) * _day});
      final mixed = run(
        only(
          settings: const ExportSettings(
            historyLimit: 10,
            pasteMode: 'copy_only',
          ),
        ),
        settings: true,
      );
      expect(mixed.limitKept, isTrue);
      expect(mixed.settingsApplied, isTrue);
      final again = run(
        only(
          settings: const ExportSettings(
            historyLimit: 10,
            pasteMode: 'copy_only',
          ),
        ),
        settings: true,
      );
      expect(again.limitKept, isTrue);
      expect(again.settingsApplied, isFalse);
    });

    test('a new ignored app is a change; the same app again, or one that '
        'is on the list under another name, is not', () {
      final first = run(
        only(apps: const [IgnoredApp('com.vault', 'Vault')]),
        settings: true,
      );
      expect(first.settingsApplied, isTrue);
      final again = run(
        only(apps: const [IgnoredApp('com.vault', 'Vault')]),
        settings: true,
      );
      expect(again.settingsApplied, isFalse);
      final renamed = run(
        only(apps: const [IgnoredApp('com.vault', 'Another name')]),
        settings: true,
      );
      expect(renamed.settingsApplied, isFalse);
      final list = store.ignoredAppStore().list();
      expect(
        list.where((a) => a.appId == 'com.vault').single.displayName,
        'Vault',
      );
    });

    test('a preset already on the list is not a change; one the user '
        'removed that comes back is', () {
      final preset = presetIgnoredApps.first;
      final onList = run(
        only(apps: [IgnoredApp(preset.appId, preset.displayName)]),
        settings: true,
      );
      expect(onList.settingsApplied, isFalse);
      final db = raw();
      db.execute('DELETE FROM ignored_apps WHERE app_id = ?', [preset.appId]);
      db.close();
      final back = run(
        only(apps: [IgnoredApp(preset.appId, preset.displayName)]),
        settings: true,
      );
      expect(back.settingsApplied, isTrue);
    });

    test('a new app next to settings that are all in use or kept: still '
        'applied', () {
      final c = run(
        only(settings: current(), apps: const [IgnoredApp('com.new', 'New')]),
        settings: true,
      );
      expect(c.settingsApplied, isTrue);
    });

    test('a file with an empty settings object and no apps: not applied', () {
      final c = run(
        only(settings: const ExportSettings(), apps: const []),
        settings: true,
      );
      expect(c.settingsApplied, isFalse);
    });

    test('BUG-R11 (Low): a setting the file repeats at its default, where no '
        'row is stored yet (paste mode "auto" on a fresh database), is not '
        'counted as a change', () {
      // put() compares with the stored row, and a missing row counts as
      // "different", so the toast says "Imported the settings and ignored
      // apps in this file." although nothing the user can see changed.
      expect(rawSetting('paste_mode'), isNull, reason: 'fresh database');
      final c = run(
        only(settings: const ExportSettings(pasteMode: 'auto')),
        settings: true,
      );
      expect(c.settingsApplied, isFalse);
    });
  });
}
