// M1.7 tester: auto-delete against the real encrypted SQLite store
// (docs/design/settings-and-expiry.md "Auto-delete", "Trust boundaries and
// abuse cases"): the cutoff boundary, one transaction for save + delete, a
// crafted setting value, extreme cutoffs, and snippets (R2).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _day = Duration.millisecondsPerDay;
const _minInt = -0x8000000000000000;
const _maxInt = 0x7fffffffffffffff;

void main() {
  late Directory dir;
  late String path;
  late SqliteHistoryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_expiry_edge_');
    path = '${dir.path}/kusunga.db';
    store = SqliteHistoryStore.open(path: path, keyHex: _key);
  });
  tearDown(() {
    try {
      store.close();
    } catch (_) {}
    dir.deleteSync(recursive: true);
  });

  Database raw() => sqlite3.open(path)..execute("PRAGMA hexkey = '$_key'");

  List<String> previews(List<ClipItem> items) => [
    for (final i in items) i.preview,
  ];

  group('the cutoff boundary: an item last copied exactly at it is kept', () {
    test('listSince keeps >= cutoff and drops one millisecond older', () {
      const cut = 50 * _day;
      store.insertOrBump('older', ClipKind.text, cut - 1);
      store.insertOrBump('exact', ClipKind.text, cut);
      store.insertOrBump('newer', ClipKind.text, cut + 1);
      expect(previews(store.listSince(cut)), ['newer', 'exact']);
    });

    test('deleteOlderThan removes only < cutoff', () {
      const cut = 50 * _day;
      store.insertOrBump('older', ClipKind.text, cut - 1);
      store.insertOrBump('exact', ClipKind.text, cut);
      expect(store.deleteOlderThan(cut), 1);
      expect(previews(store.list()), ['exact']);
    });

    test('countOlderThan: < cutoff and >= notBefore, both edges exact', () {
      store.insertOrBump('a', ClipKind.text, 10);
      store.insertOrBump('b', ClipKind.text, 20);
      store.insertOrBump('c', ClipKind.text, 30);
      expect(store.countOlderThan(30, notBefore: 20), 1); // b only
      expect(store.countOlderThan(31, notBefore: 20), 2); // b, c
      expect(store.countOlderThan(30, notBefore: 21), 0);
      expect(store.countOlderThan(30), 2);
    });

    for (final days in [1, 7, 30]) {
      test('$days day(s) is exactly $days x 24 h of epoch time (no DST)', () {
        const now = 400 * _day + 12345;
        final cut = now - days * Duration.hoursPerDay * 3600 * 1000;
        // Oldest first: the store never saves older than its newest item.
        store.insertOrBump('gone', ClipKind.text, cut - 1);
        store.insertOrBump('edge', ClipKind.text, cut);
        expect(previews(store.listSince(cut)), ['edge']);
        expect(store.deleteOlderThan(cut), 1);
        expect(previews(store.list()), ['edge']);
      });
    }
  });

  group('re-copy and snippets', () {
    test('a re-copy bumps last_copied_at, so the old item survives the '
        'clean-up (D2 A)', () {
      store.insertOrBump('same', ClipKind.text, 1 * _day);
      store.insertOrBump('same', ClipKind.text, 99 * _day);
      expect(store.deleteOlderThan(50 * _day), 0);
      final item = store.list().single;
      expect(item.createdAt, 1 * _day);
      expect(item.lastCopiedAt, 99 * _day);
    });

    test('a snippet with the same text as an expired item stays (R2)', () {
      store.snippetStore().insert(
        name: 'Phone',
        content: '07700 900123',
        type: SnippetType.other,
        nowMs: 1,
      );
      store.insertOrBump('07700 900123', ClipKind.text, 1);
      expect(store.setExpiryDays(1, deleteBefore: 10 * _day), 1);
      expect(store.list(), isEmpty);
      final s = store.snippetStore().list().single;
      expect(s.name, 'Phone');
      expect(store.snippetStore().contentOf(s.id), '07700 900123');
    });
  });

  group('one transaction for save + delete', () {
    void failDeletesOf(String content) {
      final db = raw();
      db.execute(
        'CREATE TRIGGER boom BEFORE DELETE ON clip_items '
        "WHEN old.content = '$content' "
        "BEGIN SELECT RAISE(ABORT, 'nope'); END",
      );
      db.close();
    }

    test('a failing delete keeps the old setting and every item', () {
      store.setExpiryDays(7);
      store.insertOrBump('x1', ClipKind.text, 1);
      store.insertOrBump('boom', ClipKind.text, 2);
      store.insertOrBump('x3', ClipKind.text, 3);
      store.insertOrBump('keep', ClipKind.text, 100 * _day);
      failDeletesOf('boom');
      expect(
        () => store.setExpiryDays(1, deleteBefore: 50 * _day),
        throwsA(anything),
      );
      expect(store.readSetting(historyExpirySetting), '7');
      expect(store.list().length, 4, reason: 'nothing was deleted');
    });

    test('deleteOlderThan is all or nothing', () {
      store.insertOrBump('x1', ClipKind.text, 1);
      store.insertOrBump('boom', ClipKind.text, 2);
      store.insertOrBump('keep', ClipKind.text, 100 * _day);
      failDeletesOf('boom');
      expect(() => store.deleteOlderThan(50 * _day), throwsA(anything));
      expect(store.list().length, 3);
      // The store is still usable after the rollback.
      expect(store.insertOrBump('later', ClipKind.text, 101 * _day), isNonZero);
    });

    test('only 0, 1, 7 and 30 are written; nothing changes otherwise', () {
      store.setExpiryDays(7);
      for (final bad in [-1, 2, 365, _maxInt, _minInt]) {
        expect(() => store.setExpiryDays(bad), throwsArgumentError);
      }
      expect(store.readSetting(historyExpirySetting), '7');
    });
  });

  group('extreme cutoffs do not crash', () {
    test('minimum and maximum integers', () {
      store.insertOrBump('a', ClipKind.text, 5);
      expect(store.listSince(_minInt).length, 1);
      expect(store.listSince(_maxInt), isEmpty);
      expect(store.countOlderThan(_minInt), 0);
      expect(store.countOlderThan(_maxInt, notBefore: _minInt), 1);
      expect(store.deleteOlderThan(_minInt), 0);
      expect(store.deleteOlderThan(_maxInt), 1);
    });
  });

  group(
    'a crafted history_expiry_days in the file means Never (abuse case)',
    () {
      // Stored as text or as a number: the column has TEXT affinity, so a
      // number becomes text, but a blob or NULL is kept as is.
      final crafted = <String, Object?>{
        '-1': '-1',
        '2': '2',
        '365': '365',
        'huge': '99999999999999999999',
        'int max': '9223372036854775807',
        'hex': '0x7',
        'empty': '',
        'text': 'thirty',
        'arabic digit': '٧',
        'sql': "7'; DELETE FROM clip_items; --",
        'blob': [0x37],
      };
      for (final e in crafted.entries) {
        test('${e.key}: nothing is deleted, Never, readFailed logged', () {
          store.insertOrBump('ancient', ClipKind.text, 1);
          final db = raw();
          db.execute(
            "UPDATE settings SET value = ? WHERE key = 'history_expiry_days'",
            [e.value],
          );
          db.close();
          final log = FakeLog();
          final service = HistoryService(
            store: store,
            source: FakeClipboardSource(),
            log: log,
            clock: () => 1000 * _day,
            writeClipboard: (_) async {},
          )..start();
          addTearDown(service.dispose);
          expect(service.expiry.days, 0);
          expect(previews(service.items), ['ancient']);
          expect(log.codes, contains(LogCode.readFailed));
          expect(log.codes, isNot(contains(LogCode.historyExpired)));
        });
      }

      test('each valid value, stored as a number, is read', () {
        for (final d in historyExpiryChoices) {
          final db = raw();
          db.execute(
            "UPDATE settings SET value = ? WHERE key = 'history_expiry_days'",
            [d],
          );
          db.close();
          final service = HistoryService(
            store: store,
            source: FakeClipboardSource(),
            log: FakeLog(),
            writeClipboard: (_) async {},
          )..start();
          expect(service.expiry.days, d);
          service.dispose();
        }
      });
    },
  );

  group('migration', () {
    test('reopening a v6 file twice keeps the user\'s value and the rows', () {
      store.setExpiryDays(7);
      store.insertOrBump('a', ClipKind.text, 1);
      store.close();
      for (var i = 0; i < 2; i++) {
        final s = SqliteHistoryStore.open(path: path, keyHex: _key);
        expect(s.readSetting(historyExpirySetting), '7');
        expect(s.list().length, 1);
        s.close();
      }
      store = SqliteHistoryStore.open(path: path, keyHex: _key);
    });

    test('a new file is 30 days and the setting row is unique', () {
      final db = raw();
      final rows = db.select(
        "SELECT count(*) AS n FROM settings WHERE key = 'history_expiry_days'",
      );
      db.close();
      expect(rows.single['n'], 1);
      expect(store.readSetting(historyExpirySetting), '30');
    });
  });
}
