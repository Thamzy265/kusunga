// M1.8 import into the encrypted store (docs/design/your-data.md, "Merge",
// "One transaction"; lead rulings G5 2026-11-12) and Delete all history's
// VACUUM (D4 A).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:sqlite3/sqlite3.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _now = 1700000000000;

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
    dir = Directory.systemTemp.createTempSync('kusunga_import_');
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

  SnippetStore snippets() => store.snippetStore();

  void addSnippet(String name, {String? content, String? shortcut}) =>
      snippets().insert(
        name: name,
        content: content ?? 'content of $name',
        type: SnippetType.other,
        nowMs: 1,
        shortcut: shortcut,
      );

  List<String> names() => [for (final s in snippets().list()) s.name];

  group('snippets merge, never overwrite (D3 A)', () {
    test('added after the existing ones, in the file order', () {
      addSnippet('Mine');
      final c = store.importBundle(
        ExportBundle(snippets: [_s('B', p: 1), _s('A', p: 0)]),
        applySettings: false,
        nowMs: _now,
      );
      expect(names(), ['Mine', 'A', 'B']);
      expect(snippets().list().map((s) => s.position), [0, 1, 2]);
      expect(c.snippetsAdded, 2);
      expect(c.snippetsAlreadyHere, 0);
    });

    test('the same name and content is skipped; same name, other content is '
        'added', () {
      addSnippet('Phone', content: '123');
      final c = store.importBundle(
        ExportBundle(
          snippets: [
            _s('Phone', content: '123'),
            _s('Phone', content: '456'),
            _s('Phone', content: '456'), // twice in the file
          ],
        ),
        applySettings: false,
        nowMs: _now,
      );
      expect(c.snippetsAdded, 1);
      expect(c.snippetsAlreadyHere, 2);
      expect(names(), ['Phone', 'Phone']);
    });

    test('a shortcut already used, or the start of one, is dropped: the '
        'snippet is still added', () {
      addSnippet('Email', shortcut: ';email');
      final c = store.importBundle(
        ExportBundle(
          snippets: [
            _s('Same', shortcut: ';email'),
            _s('Prefix', shortcut: ';em'),
            _s('Longer', shortcut: ';emailx'),
            _s('Free', shortcut: ';ph'),
            _s('Clashes with the file', shortcut: ';ph'),
          ],
        ),
        applySettings: false,
        nowMs: _now,
      );
      expect(c.snippetsAdded, 5);
      expect(c.shortcutsDropped, 4);
      final byName = {for (final s in snippets().list()) s.name: s.shortcut};
      expect(byName['Email'], ';email', reason: 'existing never changed');
      expect(byName['Same'], isNull);
      expect(byName['Prefix'], isNull);
      expect(byName['Longer'], isNull);
      expect(byName['Free'], ';ph');
      expect(byName['Clashes with the file'], isNull);
    });

    test('past 1,000 snippets in all: nothing is imported', () {
      final db = raw();
      for (var i = 0; i < SnippetStore.maxCount - 1; i++) {
        db.execute(
          'INSERT INTO snippets (name, content, type, position, created_at, '
          "updated_at) VALUES ('n$i', 'c$i', 'other', $i, 1, 1)",
        );
      }
      db.close();
      expect(
        () => store.importBundle(
          ExportBundle(
            snippets: [_s('A'), _s('B')],
            history: [_h('h', _now, _now)],
          ),
          applySettings: false,
          nowMs: _now,
        ),
        throwsA(isA<SnippetCapReached>()),
      );
      expect(snippets().count, SnippetStore.maxCount - 1);
      expect(store.count, 0);
    });
  });

  group('history (lead ruling G5)', () {
    test('keeps the file times; a duplicate merges like Undo', () {
      store.insertOrBump('both', ClipKind.text, 5000);
      final c = store.importBundle(
        ExportBundle(
          snippets: const [],
          history: [_h('both', 1000, 9000), _h('new', 2000, 3000)],
        ),
        applySettings: false,
        nowMs: _now,
      );
      expect(c.historyAdded, 1, reason: '"both" merged: no new row (T4)');
      final items = store.list();
      expect(items.map((i) => i.preview), ['both', 'new']);
      expect(items.first.createdAt, 1000, reason: 'the older creation');
      expect(items.first.lastCopiedAt, 9000, reason: 'the newer last copy');
      expect(items.last.createdAt, 2000);
      expect(items.last.lastCopiedAt, 3000);
    });

    test('a duplicate whose file copy is older keeps the newer time here', () {
      store.insertOrBump('both', ClipKind.link, 9000);
      store.importBundle(
        ExportBundle(snippets: const [], history: [_h('both', 100, 200)]),
        applySettings: false,
        nowMs: _now,
      );
      final item = store.list().single;
      expect(item.lastCopiedAt, 9000);
      expect(item.createdAt, 100);
      expect(item.kind, ClipKind.link, reason: 'existing kind kept');
    });

    test('items older than the auto-delete time are not added', () {
      final c = store.importBundle(
        ExportBundle(
          snippets: const [],
          history: [_h('old', 1, 999), _h('edge', 1, 1000), _h('new', 1, 5000)],
        ),
        applySettings: false,
        notBefore: 1000,
        nowMs: _now,
      );
      expect(c.historyAdded, 2);
      expect(c.historyTooOld, 1);
      expect(store.list().map((i) => i.preview), ['new', 'edge']);
    });

    test('trimmed to the limit, newest kept', () {
      store.setLimit(10);
      store.importBundle(
        ExportBundle(
          snippets: const [],
          history: [for (var i = 0; i < 15; i++) _h('h$i', i, i + 100)],
        ),
        applySettings: false,
        nowMs: _now,
      );
      expect(store.count, 10);
      expect(store.list().first.preview, 'h14');
      expect(store.list().last.preview, 'h5');
    });

    test('the history count is rows added: a line repeated in the file '
        'counts once, a line already here and one trimmed past the limit '
        'not at all (T4)', () {
      store.setLimit(10);
      for (var i = 0; i < 8; i++) {
        store.insertOrBump('mine $i', ClipKind.text, 1000 + i);
      }
      final c = store.importBundle(
        ExportBundle(
          snippets: const [],
          history: [
            _h('twice', 1, 5000),
            _h('twice', 1, 5000),
            _h('mine 7', 1, 6000), // already here
            _h('new', 1, 4000),
            _h('too far down', 1, 10), // past the limit after the trim
          ],
        ),
        applySettings: false,
        nowMs: _now,
      );
      expect(c.historyAdded, 2);
      expect(c.historyNoRoom, 1);
      expect(store.count, 10);
      expect(
        store.list().map((i) => i.preview).where((p) => !p.startsWith('mine')),
        ['twice', 'new'],
      );
    });

    group('never deletes an item here (R1, PM decision 2026-11-13)', () {
      List<String> mine() => [
        for (final i in store.list())
          if (i.preview.startsWith('mine')) i.preview,
      ];

      test('a full history keeps every item; newer items from the file '
          "don't fit and are counted", () {
        store.setLimit(10);
        for (var i = 0; i < 10; i++) {
          store.insertOrBump('mine $i', ClipKind.text, 1000 + i);
        }
        final before = mine();
        final c = store.importBundle(
          ExportBundle(
            snippets: const [],
            history: [_h('a', 1, 9000), _h('b', 1, 8000), _h('c', 1, 7000)],
          ),
          applySettings: false,
          nowMs: _now,
        );
        expect(c.historyAdded, 0);
        expect(c.historyNoRoom, 3);
        expect(mine(), before);
        expect(store.count, 10);
      });

      test('the free room is filled newest first; the rest are counted', () {
        store.setLimit(10);
        for (var i = 0; i < 7; i++) {
          store.insertOrBump('mine $i', ClipKind.text, 5000 + i);
        }
        final c = store.importBundle(
          ExportBundle(
            snippets: const [],
            history: [
              _h('old', 1, 100),
              _h('newest', 1, 9000),
              _h('older', 1, 200),
              _h('newer', 1, 8000),
              _h('mid', 1, 300),
            ],
          ),
          applySettings: false,
          nowMs: _now,
        );
        expect(c.historyAdded, 3);
        expect(c.historyNoRoom, 2);
        expect(mine(), hasLength(7));
        expect(
          store
              .list()
              .map((i) => i.preview)
              .where((p) => !p.startsWith('mine')),
          ['newest', 'newer', 'mid'],
        );
      });

      test('a text already shown merges into its item and needs no room', () {
        store.setLimit(10);
        for (var i = 0; i < 10; i++) {
          store.insertOrBump('mine $i', ClipKind.text, 1000 + i);
        }
        final c = store.importBundle(
          ExportBundle(snippets: const [], history: [_h('mine 0', 1, 9000)]),
          applySettings: false,
          nowMs: _now,
        );
        expect(c.historyAdded, 0);
        expect(c.historyNoRoom, 0);
        expect(store.list().first.preview, 'mine 0');
        expect(store.list().first.lastCopiedAt, 9000);
        expect(store.count, 10);
      });

      test('a hidden, expired item the file would bring back needs room: '
          'without it, it stays as it was', () {
        store.setLimit(10);
        store.insertOrBump('hidden', ClipKind.text, 10);
        for (var i = 0; i < 9; i++) {
          store.insertOrBump('mine $i', ClipKind.text, 1000 + i);
        }
        // 9 shown under 10: room for one, which the newer item takes.
        final c = store.importBundle(
          ExportBundle(
            snippets: const [],
            history: [_h('hidden', 1, 9000), _h('newer', 1, 9500)],
          ),
          applySettings: false,
          notBefore: 500,
          nowMs: _now,
        );
        expect(c.historyNoRoom, 1);
        expect(c.historyAdded, 1);
        expect(mine(), hasLength(9));
        expect(
          store.records().firstWhere((r) => r.content == 'hidden').lastCopiedAt,
          10,
        );
      });

      test('ticked: a lower limit that would delete a shown item is kept; '
          'the other settings and the apps still apply', () {
        for (var i = 0; i < 30; i++) {
          store.insertOrBump('mine $i', ClipKind.text, _now - i);
        }
        final c = store.importBundle(
          const ExportBundle(
            snippets: [],
            settings: ExportSettings(
              historyLimit: 25,
              typedShortcutsOn: true,
              pasteMode: 'copy_only',
            ),
            ignoredApps: [IgnoredApp('com.example.vault', 'Vault')],
          ),
          applySettings: true,
          notBefore: _now - 30 * Duration.millisecondsPerDay,
          nowMs: _now,
        );
        expect(c.limitKept, isTrue);
        expect(c.expiryKept, isFalse);
        expect(store.limit, 200);
        expect(store.count, 30);
        expect(store.readSetting('typed_shortcuts_on'), '1');
        expect(store.readSetting('paste_mode'), 'copy_only');
        expect(
          store.ignoredAppStore().list().any(
            (a) => a.appId == 'com.example.vault',
          ),
          isTrue,
        );
      });

      test('ticked: a lower limit that every shown item fits under is '
          'applied, and the file fills only what is left', () {
        for (var i = 0; i < 20; i++) {
          store.insertOrBump('mine $i', ClipKind.text, _now - i);
        }
        final c = store.importBundle(
          ExportBundle(
            snippets: const [],
            history: [
              for (var i = 0; i < 10; i++) _h('t$i', 1, _now - 100 - i),
            ],
            settings: const ExportSettings(historyLimit: 25),
          ),
          applySettings: true,
          nowMs: _now,
        );
        expect(c.limitKept, isFalse);
        expect(store.limit, 25);
        expect(c.historyAdded, 5);
        expect(c.historyNoRoom, 5);
        expect(mine(), hasLength(20));
      });

      test('ticked: a shorter auto-delete time that would delete a shown '
          'item is kept; one that only reaches items already hidden is '
          'applied', () {
        const day = Duration.millisecondsPerDay;
        store.insertOrBump('three days old', ClipKind.text, _now - 3 * day);
        store.insertOrBump('today', ClipKind.text, _now);
        final kept = store.importBundle(
          const ExportBundle(
            snippets: [],
            settings: ExportSettings(historyExpiryDays: 1),
          ),
          applySettings: true,
          notBefore: _now - 30 * day,
          nowMs: _now,
        );
        expect(kept.expiryKept, isTrue);
        expect(store.readSetting(historyExpirySetting), '30');
        // With a 1-day auto-delete in use, the 3-day-old item is already
        // hidden: 1 day (the same) is applied.
        final applied = store.importBundle(
          const ExportBundle(
            snippets: [],
            settings: ExportSettings(historyExpiryDays: 7),
          ),
          applySettings: true,
          notBefore: _now - 2 * day,
          nowMs: _now,
        );
        expect(applied.expiryKept, isFalse);
        expect(store.readSetting(historyExpirySetting), '7');
        expect(store.count, 2);
      });

      test('ticked: both kept, and items older than the kept auto-delete '
          'time are too old', () {
        const day = Duration.millisecondsPerDay;
        // Oldest first: a copy is never saved older than the newest one.
        for (var i = 9; i >= 0; i--) {
          store.insertOrBump('mine $i', ClipKind.text, _now - i * day);
        }
        final c = store.importBundle(
          ExportBundle(
            snippets: const [],
            history: [_h('two days', 1, _now - 2 * day)],
            settings: const ExportSettings(
              historyLimit: 10,
              historyExpiryDays: 1,
            ),
          ),
          applySettings: true,
          notBefore: _now - 30 * day,
          nowMs: _now,
        );
        expect(c.limitKept, isFalse, reason: '10 shown fit under 10');
        expect(c.expiryKept, isTrue);
        expect(c.historyTooOld, 0, reason: 'the 30 days in use decide');
        expect(c.historyNoRoom, 1);
        expect(store.count, 10);
      });
    });

    test('the whole text of a long item, not a preview', () {
      final long = 'x' * (ClipItem.previewLength * 3);
      store.importBundle(
        ExportBundle(snippets: const [], history: [_h(long, 1, 2)]),
        applySettings: false,
        nowMs: _now,
      );
      expect(store.contentOf(store.list().single.id), long);
    });
  });

  group('settings and ignored apps only when ticked (D5 A)', () {
    const settings = ExportSettings(
      historyLimit: 20,
      historyExpiryDays: 7,
      typedShortcutsOn: true,
      pasteMode: 'copy_only',
    );
    const apps = [
      IgnoredApp('com.example.vault', 'Vault'),
      IgnoredApp('com.1password.1password', 'Renamed'),
    ];

    test('not ticked: nothing changes', () {
      final before = store.ignoredAppStore().list().length;
      store.importBundle(
        const ExportBundle(snippets: [], settings: settings, ignoredApps: apps),
        applySettings: false,
        nowMs: _now,
      );
      expect(store.limit, 200);
      expect(store.readSetting(historyExpirySetting), '30');
      expect(store.readSetting('typed_shortcuts_on'), '0');
      expect(store.readSetting('paste_mode'), isNull);
      expect(store.ignoredAppStore().list().length, before);
    });

    test('ticked: saved, the limit in use changes, apps only added', () {
      store.ignoredAppStore().remove('com.bitwarden.desktop');
      final before = store.ignoredAppStore().list();
      store.importBundle(
        ExportBundle(
          snippets: const [],
          history: [for (var i = 0; i < 30; i++) _h('h$i', i, _now - i)],
          settings: settings,
          ignoredApps: apps,
        ),
        applySettings: true,
        nowMs: _now,
      );
      expect(store.limit, 20);
      expect(store.count, 20, reason: 'the room under the new limit');
      expect(store.readSetting(historyExpirySetting), '7');
      expect(store.readSetting('typed_shortcuts_on'), '1');
      expect(store.readSetting('paste_mode'), 'copy_only');
      final after = store.ignoredAppStore().list();
      expect(after.length, before.length + 1);
      expect(after.last.appId, 'com.example.vault');
      expect(after.last.preset, isFalse);
      expect(
        after
            .firstWhere((a) => a.appId == 'com.1password.1password')
            .displayName,
        '1Password',
        reason: 'an existing entry is never changed',
      );
      expect(
        after.any((a) => a.appId == 'com.bitwarden.desktop'),
        isFalse,
        reason: 'only what the file has is added',
      );
    });

    test('a preset id the user had removed comes back marked as a preset', () {
      store.ignoredAppStore().remove('com.bitwarden.desktop');
      store.importBundle(
        const ExportBundle(
          snippets: [],
          ignoredApps: [IgnoredApp('com.bitwarden.desktop', 'Bitwarden')],
        ),
        applySettings: true,
        nowMs: _now,
      );
      expect(
        store
            .ignoredAppStore()
            .list()
            .firstWhere((a) => a.appId == 'com.bitwarden.desktop')
            .preset,
        isTrue,
      );
    });
  });

  group('preview (T4): the counts an import would give, changing nothing', () {
    List<Object?> dump() {
      final db = raw();
      try {
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

    final bundle = ExportBundle(
      snippets: [_s('A'), _s('Mine')],
      history: [
        _h('dup', 1, 5000),
        _h('dup', 1, 5000),
        _h('here', 1, 6000),
        for (var i = 0; i < 12; i++) _h('h$i', 1, 100 + i),
      ],
      settings: const ExportSettings(historyLimit: 50, typedShortcutsOn: true),
      ignoredApps: const [IgnoredApp('com.example.vault', 'Vault')],
    );

    for (final apply in [false, true]) {
      test('applySettings $apply: the same counts as the import, and every '
          'table and the limit in use are as they were', () {
        store.setLimit(10);
        addSnippet('Mine');
        store.insertOrBump('here', ClipKind.text, 3000);
        final before = dump();
        final preview = store.previewImport(
          bundle,
          applySettings: apply,
          nowMs: _now,
        );
        expect(dump(), before);
        expect(store.limit, 10);
        final done = store.importBundle(
          bundle,
          applySettings: apply,
          nowMs: _now,
        );
        expect(preview.historyAdded, done.historyAdded);
        expect(preview.historyAdded, apply ? 13 : 9);
        expect(preview.snippetsAdded, done.snippetsAdded);
        expect(preview.snippetsAlreadyHere, done.snippetsAlreadyHere);
        expect(preview.historyTooOld, done.historyTooOld);
      });
    }

    test('a preview that fails (over 1,000 snippets) changes nothing and the '
        'store still works', () {
      for (var i = 0; i < SnippetStore.maxCount; i++) {
        addSnippet('n$i');
      }
      final before = dump();
      expect(
        () => store.previewImport(
          ExportBundle(snippets: [_s('one more')]),
          applySettings: false,
          nowMs: _now,
        ),
        throwsA(isA<SnippetCapReached>()),
      );
      expect(dump(), before);
      store.insertOrBump('after', ClipKind.text, 1);
      expect(store.count, 1);
    });
  });

  test('a write failure mid-import rolls everything back', () {
    addSnippet('Mine', shortcut: ';m');
    store.insertOrBump('kept', ClipKind.text, 10);
    final appsBefore = store.ignoredAppStore().list().length;
    final db = raw();
    db.execute(
      'CREATE TRIGGER fail BEFORE INSERT ON clip_items '
      "WHEN NEW.content = 'boom' BEGIN SELECT RAISE(ABORT, 'disk'); END",
    );
    db.close();
    expect(
      () => store.importBundle(
        ExportBundle(
          snippets: [
            _s('A'),
            _s('B', shortcut: ';b'),
          ],
          history: [_h('fine', 1, 20), _h('boom', 1, 30)],
          settings: const ExportSettings(historyLimit: 50),
          ignoredApps: const [IgnoredApp('x.y', 'X')],
        ),
        applySettings: true,
        nowMs: _now,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(names(), ['Mine']);
    expect(store.list().map((i) => i.preview), ['kept']);
    expect(store.limit, 200);
    expect(store.readSetting('typed_shortcuts_on'), '0');
    expect(store.ignoredAppStore().list().length, appsBefore);
    // The store still works afterwards.
    store.insertOrBump('after', ClipKind.text, 40);
    expect(store.count, 2);
  });

  group('export reads', () {
    test('records: whole text, newest first, without expired items', () {
      final long = 'y' * (ClipItem.previewLength + 5);
      store.insertOrBump('old', ClipKind.text, 100);
      store.insertOrBump(long, ClipKind.text, 200);
      store.insertOrBump('https://a.b', ClipKind.link, 300);
      final all = store.records();
      expect(all.map((r) => r.content), ['https://a.b', long, 'old']);
      expect(all.first.kind, ClipKind.link);
      expect(store.records(notBefore: 200).map((r) => r.lastCopiedAt), [
        300,
        200,
      ]);
    });

    test('snippet records: whole text, shortcut and order', () {
      addSnippet('B', content: 'b' * 9000, shortcut: ';b');
      addSnippet('A');
      snippets().move(snippets().list().last.id, 0);
      final r = snippets().records();
      expect(r.map((s) => s.name), ['A', 'B']);
      expect(r.map((s) => s.position), [0, 1]);
      expect(r.last.content, 'b' * 9000);
      expect(r.last.shortcut, ';b');
    });

    test('the memory stores give the same records', () {
      final mem = MemoryHistoryStore()
        ..insertOrBump('a', ClipKind.text, 1)
        ..insertOrBump('b', ClipKind.text, 2);
      expect(mem.records().map((r) => r.content), ['b', 'a']);
      expect(mem.records(notBefore: 2).map((r) => r.content), ['b']);
      final ms = MemorySnippetStore()
        ..insert(
          name: 'N',
          content: 'C',
          type: SnippetType.email,
          nowMs: 1,
          shortcut: ';n',
        );
      expect(ms.records().single.shortcut, ';n');
      expect(ms.records().single.type, SnippetType.email);
    });

    test('a memory store never previews an import either (G2)', () {
      expect(
        () => MemoryHistoryStore().previewImport(
          const ExportBundle(snippets: []),
          applySettings: false,
          nowMs: 1,
        ),
        throwsUnsupportedError,
      );
    });

    test('a memory store never imports (Import is off there, G2)', () {
      expect(
        () => MemoryHistoryStore().importBundle(
          const ExportBundle(snippets: []),
          applySettings: false,
          nowMs: 1,
        ),
        throwsUnsupportedError,
      );
    });
  });

  test('compact (VACUUM) after Clear history shrinks the file (D4 A)', () {
    for (var i = 0; i < 300; i++) {
      store.insertOrBump('item $i ${'z' * 4000}', ClipKind.text, i + 1);
    }
    store.setLimit(5000);
    store.clear();
    final before = File(path).lengthSync() + _wal(path);
    store.compact();
    final after = File(path).lengthSync() + _wal(path);
    expect(after, lessThan(before ~/ 4));
    expect(store.count, 0);
    store.insertOrBump('still works', ClipKind.text, 1);
    expect(store.count, 1);
  });
}

int _wal(String path) {
  final f = File('$path-wal');
  return f.existsSync() ? f.lengthSync() : 0;
}
