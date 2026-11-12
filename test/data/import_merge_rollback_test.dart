// M1.8 tester: merge rules and rollback of the import
// (docs/design/your-data.md, "Merge (D3)", "One transaction"), against a
// real encrypted SQLite file in a temp folder. The earlier bug repros are
// fixed and run as normal tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _now = 1700000000000;
const _day = Duration.millisecondsPerDay;

ExportSnippet _s(String name, {String? content, String? shortcut, int p = 0}) =>
    ExportSnippet(
      name: name,
      content: content ?? 'content of $name',
      type: SnippetType.other,
      position: p,
      shortcut: shortcut,
    );

ExportHistoryItem _h(String content, int created, int last) =>
    ExportHistoryItem(
      content: content,
      kind: ClipKind.text,
      createdAt: created,
      lastCopiedAt: last,
    );

void main() {
  late Directory dir;
  late String path;
  late SqliteHistoryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_import_');
    path = '${dir.path}/kusunga.db';
    store = SqliteHistoryStore.open(path: path, keyHex: _key);
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  /// Every row of every table, in a fixed order: "byte-identical in
  /// content" for the rollback tests.
  List<Object?> dump() {
    final db = sqlite3.open(path);
    try {
      db.execute("PRAGMA hexkey = '$_key'");
      return [
        for (final t in [
          'snippets ORDER BY id',
          'clip_items ORDER BY id',
          'settings ORDER BY key',
          'ignored_apps ORDER BY app_id',
        ])
          [for (final r in db.select('SELECT * FROM $t')) r.values.toList()],
      ];
    } finally {
      db.close();
    }
  }

  SnippetStore snippets() => store.snippetStore();

  void seed() {
    snippets().insert(
      name: 'Mine',
      content: 'mine',
      type: SnippetType.other,
      nowMs: 1,
      shortcut: ';mine',
    );
    store.insertOrBump('existing item', ClipKind.text, _now - 5 * _day);
    store.setLimit(100);
  }

  ImportCounts doImport(
    ExportBundle b, {
    bool settings = false,
    int? notBefore,
  }) => store.importBundle(
    b,
    applySettings: settings,
    notBefore: notBefore,
    nowMs: _now,
  );

  group('importing the same file twice changes nothing the second time', () {
    test('snippets, history, settings and ignored apps', () {
      seed();
      final bundle = ExportBundle(
        snippets: [
          _s('A', shortcut: ';a', p: 0),
          _s('B', p: 1),
        ],
        history: [
          _h('one', _now - 3 * _day, _now - 2 * _day),
          _h('two', _now - 3 * _day, _now - _day),
        ],
        settings: const ExportSettings(
          historyLimit: 50,
          historyExpiryDays: 7,
          typedShortcutsOn: true,
          pasteMode: 'copy_only',
        ),
        ignoredApps: const [IgnoredApp('com.example.vault', 'Vault')],
      );
      final first = doImport(bundle, settings: true);
      expect(first.snippetsAdded, 2);
      final afterFirst = dump();
      final second = doImport(bundle, settings: true);
      expect(dump(), afterFirst, reason: 'no row, time or id changed');
      expect(second.snippetsAdded, 0);
      expect(second.snippetsAlreadyHere, 2);
      expect(second.shortcutsDropped, 0);
    });

    test('importing what was just exported gives the same content', () {
      seed();
      snippets().insert(
        name: 'Second',
        content: 'two\nlines 😀',
        type: SnippetType.address,
        nowMs: 2,
      );
      final before = dump();
      final records = [
        for (final s in snippets().records())
          ExportSnippet(
            name: s.name,
            content: s.content,
            type: s.type,
            position: s.position,
            shortcut: s.shortcut,
          ),
      ];
      final history = [
        for (final r in store.records())
          _h(r.content, r.createdAt, r.lastCopiedAt),
      ];
      doImport(ExportBundle(snippets: records, history: history));
      expect(dump(), before);
    });
  });

  group('merge details', () {
    test('a duplicate inside the file: one snippet, one history row', () {
      final c = doImport(
        ExportBundle(
          snippets: [_s('A'), _s('A'), _s('A', p: 5)],
          history: [_h('dup', 1, _now - _day), _h('dup', 2, _now - 2 * _day)],
        ),
      );
      expect(snippets().list(), hasLength(1));
      expect(store.records(), hasLength(1));
      expect(c.snippetsAdded, 1);
      expect(c.snippetsAlreadyHere, 2);
      final r = store.records().single;
      expect(r.createdAt, 1, reason: 'the older creation time wins');
      expect(r.lastCopiedAt, _now - _day, reason: 'the newer last copy wins');
    });

    test('the same text with another kind merges into the one row', () {
      doImport(
        ExportBundle(
          snippets: const [],
          history: [
            ExportHistoryItem(
              content: 'same',
              kind: ClipKind.text,
              createdAt: 1,
              lastCopiedAt: 2,
            ),
          ],
        ),
      );
      expect(store.records(), hasLength(1));
    });

    test('positions with gaps and ties become 0..n-1 after the existing '
        'snippets, ties in file order', () {
      seed();
      doImport(
        ExportBundle(
          snippets: [
            _s('C', p: 9),
            _s('A', p: 2),
            _s('B', p: 2),
            _s('D', p: 0),
          ],
        ),
      );
      expect(
        [for (final s in snippets().list()) s.name],
        ['Mine', 'D', 'A', 'B', 'C'],
      );
      expect([for (final s in snippets().list()) s.position], [0, 1, 2, 3, 4]);
    });

    test('a shortcut that is a prefix of an existing one, or has one as its '
        'prefix, is dropped both ways; the unrelated one stays', () {
      seed(); // ';mine'
      final c = doImport(
        ExportBundle(
          snippets: [
            _s('Short', shortcut: ';mi'),
            _s('Long', shortcut: ';mine2'),
            _s('Other', shortcut: ';zz'),
            _s('InFile', shortcut: ';zzz'), // clashes with the one just added
          ],
        ),
      );
      final by = {for (final s in snippets().list()) s.name: s.shortcut};
      expect(by['Short'], isNull);
      expect(by['Long'], isNull);
      expect(by['Other'], ';zz');
      expect(by['InFile'], isNull);
      expect(c.shortcutsDropped, 3);
      expect(c.snippetsAdded, 4);
    });

    test('exactly 1,000 snippets in all is allowed; one more fails and '
        'changes nothing', () {
      doImport(
        ExportBundle(snippets: [for (var i = 0; i < 999; i++) _s('n$i', p: i)]),
      );
      expect(snippets().list(), hasLength(999));
      final before = dump();
      // 1 new, 1 already here: 1,000 in all.
      final ok = doImport(ExportBundle(snippets: [_s('n0'), _s('last')]));
      expect(ok.snippetsAdded, 1);
      expect(ok.snippetsAlreadyHere, 1);
      expect(snippets().list(), hasLength(1000));
      final full = dump();
      expect(full, isNot(before));
      expect(
        () => doImport(ExportBundle(snippets: [_s('one too many')])),
        throwsA(isA<SnippetCapReached>()),
      );
      expect(dump(), full);
    });

    test('a file with only already-present snippets passes at the cap', () {
      doImport(
        ExportBundle(
          snippets: [for (var i = 0; i < 1000; i++) _s('n$i', p: i)],
        ),
      );
      final c = doImport(
        ExportBundle(
          snippets: [for (var i = 0; i < 1000; i++) _s('n$i', p: i)],
        ),
      );
      expect(c.snippetsAdded, 0);
      expect(c.snippetsAlreadyHere, 1000);
    });

    test('history over the limit keeps the newest, whichever file or store '
        'they came from', () {
      store.setLimit(25);
      for (var i = 24; i >= 0; i--) {
        store.insertOrBump('mine $i', ClipKind.text, _now - i * 1000);
      }
      doImport(
        ExportBundle(
          snippets: const [],
          history: [
            for (var i = 0; i < 30; i++)
              _h('theirs $i', 0, _now - 500 - i * 1000),
          ],
        ),
      );
      final kept = store.records();
      expect(kept, hasLength(25));
      expect(
        kept.map((r) => r.lastCopiedAt).toList(),
        [...kept.map((r) => r.lastCopiedAt)]..sort((a, b) => b.compareTo(a)),
      );
      expect(kept.first.content, 'mine 0');
      expect(kept.where((r) => r.content.startsWith('theirs')), isNotEmpty);
    });

    test('a ticked limit lower than what is stored trims with the new '
        'limit in the same import', () {
      for (var i = 39; i >= 0; i--) {
        store.insertOrBump('mine $i', ClipKind.text, _now - i * 1000);
      }
      doImport(
        ExportBundle(
          snippets: const [],
          settings: const ExportSettings(historyLimit: 25),
        ),
        settings: true,
      );
      expect(store.records(), hasLength(25));
      expect(store.limit, 25);
    });

    test('store level (the 24 h limit is checkImportTimes, tested apart): a '
        'history item with a time in the future is kept as it is (the '
        'newest) and does not make Undo-style merging go backwards', () {
      store.insertOrBump('x', ClipKind.text, _now);
      doImport(
        ExportBundle(
          snippets: const [],
          history: [_h('x', 0, _now + 3650 * _day)],
        ),
      );
      expect(store.records().single.lastCopiedAt, _now + 3650 * _day);
      // A second import of an older copy never lowers it.
      doImport(ExportBundle(snippets: const [], history: [_h('x', 0, 5)]));
      expect(store.records().single.lastCopiedAt, _now + 3650 * _day);
      expect(store.records().single.createdAt, 0);
    });

    test('store level (importBundle, which does not check times; '
        'checkImportTimes does that before it): a last copy before the '
        'creation is written as it is, with no error', () {
      doImport(
        ExportBundle(
          snippets: const [],
          history: [_h('odd', _now, _now - 10 * _day)],
        ),
      );
      final r = store.records().single;
      expect(r.createdAt, _now);
      expect(r.lastCopiedAt, _now - 10 * _day);
    });

    test('store level (no time check here): the oldest and newest possible '
        'times are stored and read back', () {
      const oldest = -62135596800000; // 0001-01-01
      const newest = 253402300799000; // 9999-12-31
      doImport(
        ExportBundle(
          snippets: const [],
          history: [_h('past', oldest, oldest), _h('future', newest, newest)],
        ),
      );
      expect(store.records().map((r) => r.content), ['future', 'past']);
    });

    test(
      'BUG-T4 (Low): the counts name rows, not file lines: a repeated item '
      'in the file, or one trimmed past the limit, is not counted as added',
      () {
        // The confirm dialog says "Import N history items" with N the file's
        // lines, and the toast and the log repeat it. Two identical lines
        // make one row; items beyond the limit are added and then trimmed.
        final c = doImport(
          ExportBundle(
            snippets: const [],
            history: [
              _h('dup', 1, _now - _day),
              _h('dup', 1, _now - _day),
              _h('other', 1, _now - 2 * _day),
            ],
          ),
        );
        expect(c.historyAdded, store.records().length);
      },
    );
  });

  group('rollback: a failure at each step leaves every table as it was', () {
    final goodSettings = const ExportSettings(
      historyLimit: 25,
      historyExpiryDays: 7,
      typedShortcutsOn: true,
      pasteMode: 'copy_only',
    );
    final goodApps = const [IgnoredApp('com.example.vault', 'Vault')];

    void expectRolledBack(ExportBundle bundle, Matcher failure) {
      seed();
      final before = dump();
      final limitBefore = store.limit;
      expect(() => doImport(bundle, settings: true), failure);
      expect(dump(), before);
      expect(store.limit, limitBefore, reason: 'the cached limit too');
      // The store is still usable afterwards.
      expect(doImport(ExportBundle(snippets: [_s('After')])).snippetsAdded, 1);
    }

    test('after the settings: a bad ignored app', () {
      expectRolledBack(
        ExportBundle(
          snippets: [_s('A')],
          settings: goodSettings,
          ignoredApps: const [IgnoredApp('', 'Empty id')],
        ),
        throwsArgumentError,
      );
    });

    test('after settings and apps: a snippet with a name that is too long', () {
      expectRolledBack(
        ExportBundle(
          snippets: [_s('fine'), _s('x' * 101)],
          settings: goodSettings,
          ignoredApps: goodApps,
        ),
        throwsArgumentError,
      );
    });

    test('after settings, apps and some snippets: a shortcut with a space', () {
      expectRolledBack(
        ExportBundle(
          snippets: [
            _s('fine'),
            _s('bad', shortcut: ';a b'),
          ],
          settings: goodSettings,
          ignoredApps: goodApps,
        ),
        throwsArgumentError,
      );
    });

    test('after settings, apps and snippets: an empty history item', () {
      expectRolledBack(
        ExportBundle(
          snippets: [_s('fine'), _s('also fine')],
          history: [_h('ok', 1, _now), _h('', 1, _now)],
          settings: goodSettings,
          ignoredApps: goodApps,
        ),
        throwsArgumentError,
      );
    });

    test('after everything: an over-size history item as the last one', () {
      expectRolledBack(
        ExportBundle(
          snippets: [_s('fine')],
          history: [
            for (var i = 0; i < 20; i++) _h('ok $i', 1, _now - i),
            _h('a' * (ClipItem.maxContentLength + 1), 1, _now),
          ],
          settings: goodSettings,
          ignoredApps: goodApps,
        ),
        throwsArgumentError,
      );
    });

    test('after settings and apps: the 1,000-snippet cap', () {
      for (var i = 0; i < 999; i++) {
        snippets().insert(
          name: 's$i',
          content: 'c$i',
          type: SnippetType.other,
          nowMs: 1,
        );
      }
      final before = dump();
      expect(
        () => doImport(
          ExportBundle(
            snippets: [_s('one'), _s('two')],
            history: [_h('kept out', 1, _now)],
            settings: goodSettings,
            ignoredApps: goodApps,
          ),
          settings: true,
        ),
        throwsA(isA<SnippetCapReached>()),
      );
      expect(dump(), before);
    });

    test('a bad settings value reaching the store (not through the file '
        'check) rolls back too', () {
      expectRolledBack(
        ExportBundle(
          snippets: [_s('A')],
          settings: const ExportSettings(historyLimit: 9),
        ),
        throwsArgumentError,
      );
    });
  });

  group('import while history is paused, and with auto-delete', () {
    late FakeClipboardSource source;
    late FakeLog log;
    late HistoryService service;

    setUp(() {
      source = FakeClipboardSource();
      log = FakeLog();
      service = HistoryService(
        store: store,
        source: source,
        log: log,
        clock: () => _now,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
    });
    tearDown(() async {
      await service.close();
      service.dispose();
    });

    test('while paused, imported history is still added (the user chose '
        'it), and a copy made now is still skipped', () async {
      expect(await service.pause.pause(PauseLength.untilResumed), isTrue);
      final c = service.importBundle(
        ExportBundle(
          snippets: [_s('A')],
          history: [_h('imported', 0, _now - _day)],
        ),
        applySettings: false,
      );
      expect(c.historyAdded, 1);
      expect(service.items.map((i) => i.preview), ['imported']);
      expect(service.pause.isPaused, isTrue, reason: 'import never resumes');
      source.copy('copied while paused');
      await Future<void>.delayed(Duration.zero);
      expect(service.items.map((i) => i.preview), ['imported']);
    });

    test('an ignored app in the file does not filter the imported items, and '
        'the pause is not part of a ticked import', () async {
      expect(await service.pause.pause(PauseLength.hour), isTrue);
      final until = service.pause.pausedUntil;
      service.importBundle(
        ExportBundle(
          snippets: const [],
          history: [_h('from the vault', 0, _now - _day)],
          ignoredApps: const [IgnoredApp('com.example.vault', 'Vault')],
          settings: const ExportSettings(historyLimit: 50),
        ),
        applySettings: true,
      );
      expect(service.items.map((i) => i.preview), ['from the vault']);
      expect(service.pause.pausedUntil, until);
    });

    test('a ticked, shorter auto-delete removes the imported items that '
        'fall outside it straight away', () {
      service.importBundle(
        ExportBundle(
          snippets: const [],
          history: [
            _h('ten days', 0, _now - 10 * _day),
            _h('one day', 0, _now - _day),
          ],
          settings: const ExportSettings(historyExpiryDays: 7),
        ),
        applySettings: true,
      );
      expect(service.items.map((i) => i.preview), ['one day']);
    });
  });
}
