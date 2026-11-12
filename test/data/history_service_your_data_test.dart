// M1.8: what HistoryService gives Your data — the export bundle, import with
// its live effects, Delete all history, and stopping capture for Delete
// everything (lead ruling on the order, 2026-11-12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/snippet.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _day = Duration.millisecondsPerDay;

void main() {
  late Directory dir;
  late SqliteHistoryStore store;
  late FakeClipboardSource source;
  late FakeLog log;
  late HistoryService service;
  late int now;

  HistoryService build(
    HistoryStore s, {
    Set<HistoryNotice> notices = const {},
  }) {
    final sqlite = s is SqliteHistoryStore ? s : null;
    return HistoryService(
      store: s,
      source: source,
      log: log,
      notices: notices,
      clock: () => now,
      snippetStore: sqlite?.snippetStore(),
      ignoredAppStore: sqlite?.ignoredAppStore(),
    )..start();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_yd_');
    store = SqliteHistoryStore.open(
      path: '${dir.path}/kusunga.db',
      keyHex: _key,
    );
    source = FakeClipboardSource();
    log = FakeLog();
    now = 1000 * _day;
    service = build(store);
  });
  tearDown(() async {
    await service.close();
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  group('history an import adds (T4)', () {
    ExportHistoryItem item(String content, int last) => ExportHistoryItem(
      content: content,
      kind: ClipKind.text,
      createdAt: 0,
      lastCopiedAt: last,
    );

    test('counts rows, not lines, and changes nothing; with the file\'s '
        'settings ticked, its auto-delete time and limit decide', () {
      service.setLimit(10);
      for (var i = 0; i < 10; i++) {
        store.insertOrBump('mine $i', ClipKind.text, now - i * 1000);
      }
      final bundle = ExportBundle(
        snippets: const [],
        history: [
          item('twice', now - 2 * _day),
          item('twice', now - 2 * _day),
          item('mine 0', now), // already here
          item('week old', now - 8 * _day),
          item('three weeks old', now - 21 * _day),
        ],
        settings: const ExportSettings(historyLimit: 20, historyExpiryDays: 7),
      );
      // Not ticked: limit 10, auto-delete 30 days. All of them are older
      // than the 10 items here, so all are trimmed.
      expect(service.historyToAdd(bundle, applySettings: false), 0);
      // Ticked: limit 20, auto-delete 7 days: "twice" once only.
      expect(service.historyToAdd(bundle, applySettings: true), 1);
      expect(store.count, 10);
      expect(store.limit, 10);

      final c = service.importBundle(bundle, applySettings: true);
      expect(c.historyAdded, 1);
      expect(c.historyTooOld, 2, reason: 'older than the new 7 days');
      expect(store.count, 11);
    });

    test("null where it can't be worked out: memory only, or a file the "
        'import would refuse to write', () {
      final memory = build(
        MemoryHistoryStore(),
        notices: {HistoryNotice.memoryOnly},
      );
      addTearDown(memory.dispose);
      final b = ExportBundle(snippets: const [], history: [item('x', now)]);
      expect(memory.historyToAdd(b, applySettings: false), isNull);
      for (var i = 0; i < 1000; i++) {
        store.snippetStore().insert(
          name: 'n$i',
          content: 'c',
          type: SnippetType.other,
          nowMs: 1,
        );
      }
      final tooMany = ExportBundle(
        snippets: const [
          ExportSnippet(
            name: 'one more',
            content: 'c',
            type: SnippetType.other,
            position: 0,
          ),
        ],
        history: [item('x', now)],
      );
      expect(service.historyToAdd(tooMany, applySettings: false), isNull);
    });
  });

  group('export bundle', () {
    test('snippets, the four settings and the ignore list; no history '
        'unless asked (D2 A)', () {
      service.snippets.save(
        name: 'Phone',
        content: '123',
        type: SnippetType.phone,
        shortcut: ';ph',
      );
      source.copy('copied');
      service.saveSetting('paste_mode', 'copy_only');
      service.saveSetting('picker_shortcut', 'cmd+shift+v');
      final b = service.exportBundle(includeHistory: false);
      expect(b.history, isNull);
      expect(b.snippets.single.name, 'Phone');
      expect(b.snippets.single.content, '123');
      expect(b.snippets.single.shortcut, ';ph');
      expect(b.settings!.historyLimit, 200);
      expect(b.settings!.historyExpiryDays, 30);
      expect(b.settings!.typedShortcutsOn, isFalse);
      expect(b.settings!.pasteMode, 'copy_only');
      expect(b.ignoredApps!.length, presetIgnoredApps.length);
    });

    test('with history: the shown items only, never the expired ones', () {
      store.insertOrBump('old', ClipKind.text, now - 40 * _day);
      store.insertOrBump('new', ClipKind.text, now - _day);
      final b = service.exportBundle(includeHistory: true);
      expect(b.history!.map((h) => h.content), ['new']);
    });

    test('the history count for the tick box is the shown count', () {
      store.insertOrBump('old', ClipKind.text, now - 40 * _day);
      source.copy('a');
      source.copy('b');
      expect(service.items.length, 2);
    });
  });

  group('import', () {
    test('items older than auto-delete are left out; the list refreshes', () {
      final c = service.importBundle(
        ExportBundle(
          snippets: const [],
          history: [
            ExportHistoryItem(
              content: 'too old',
              kind: ClipKind.text,
              createdAt: 0,
              lastCopiedAt: now - 31 * _day,
            ),
            ExportHistoryItem(
              content: 'recent',
              kind: ClipKind.text,
              createdAt: 0,
              lastCopiedAt: now - _day,
            ),
          ],
        ),
        applySettings: false,
      );
      expect(c.historyAdded, 1);
      expect(c.historyTooOld, 1);
      expect(
        service.historyToAdd(
          ExportBundle(
            snippets: const [],
            history: [
              ExportHistoryItem(
                content: 'x',
                kind: ClipKind.text,
                createdAt: 0,
                lastCopiedAt: now - 31 * _day,
              ),
              ExportHistoryItem(
                content: 'y',
                kind: ClipKind.text,
                createdAt: 0,
                lastCopiedAt: now,
              ),
            ],
          ),
          applySettings: false,
        ),
        1,
      );
      expect(service.items.map((i) => i.preview), ['recent']);
    });

    test('snippets show at once', () {
      service.importBundle(
        const ExportBundle(
          snippets: [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
        ),
        applySettings: false,
      );
      expect(service.snippets.items.map((s) => s.name), ['A']);
    });

    test('ticked settings take effect now: limit, auto-delete, ignore list '
        'sent to the clipboard watcher', () async {
      store.insertOrBump('20 days', ClipKind.text, now - 20 * _day);
      service.importBundle(
        const ExportBundle(
          snippets: [],
          settings: ExportSettings(historyLimit: 50, historyExpiryDays: 7),
          ignoredApps: [IgnoredApp('com.example.vault', 'Vault')],
        ),
        applySettings: true,
      );
      await pumpEventQueue();
      expect(service.limit, 50);
      expect(service.expiry.days, 7);
      expect(service.items, isEmpty, reason: 'auto-delete applied at once');
      expect(source.sentIgnored, contains('com.example.vault'));
    });

    test(
      'a failed import changes nothing and the error reaches the caller',
      () {
        final flaky = FlakyStore(store);
        final s = build(flaky);
        addTearDown(s.dispose);
        flaky.failWrites = true;
        expect(
          () => s.importBundle(
            const ExportBundle(snippets: []),
            applySettings: false,
          ),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test('canImport is false in memory-only, incompatible and backup-failed '
        'sessions (G2)', () {
      expect(service.canImport, isTrue);
      for (final n in [
        HistoryNotice.memoryOnly,
        HistoryNotice.incompatible,
        HistoryNotice.backupFailed,
      ]) {
        final s = build(MemoryHistoryStore(), notices: {n});
        expect(s.canImport, isFalse, reason: '$n');
        s.dispose();
      }
    });

    test('keychainUnusable only for a memory-only session', () {
      expect(service.keychainUnusable, isFalse);
      final m = build(
        MemoryHistoryStore(),
        notices: {HistoryNotice.memoryOnly},
      );
      expect(m.keychainUnusable, isTrue);
      m.dispose();
      final i = build(
        MemoryHistoryStore(),
        notices: {HistoryNotice.incompatible},
      );
      expect(i.keychainUnusable, isFalse);
      i.dispose();
    });
  });

  group('Delete all history (D4 A)', () {
    test('clears like Clear history, keeps snippets and settings, then '
        'compacts', () {
      service.snippets.save(
        name: 'Keep',
        content: 'k',
        type: SnippetType.other,
      );
      source.copy('a');
      source.copy('b');
      final flaky = _CompactSpy(store);
      final s = build(flaky);
      addTearDown(s.dispose);
      expect(s.deleteAllHistory(), 2);
      expect(flaky.compacts, 1);
      expect(store.count, 0);
      expect(store.snippetStore().count, 1);
    });

    test('a failed compact still reports the items deleted', () {
      source.copy('a');
      final spy = _CompactSpy(store)..failCompact = true;
      final s = build(spy);
      addTearDown(s.dispose);
      expect(s.deleteAllHistory(), 1);
      expect(log.codes, contains(LogCode.writeFailed));
    });

    test('a failed clear deletes nothing and answers null', () {
      source.copy('a');
      final flaky = FlakyStore(store)..failClear = true;
      final s = build(flaky);
      addTearDown(s.dispose);
      expect(s.deleteAllHistory(), isNull);
      expect(store.count, 1);
    });
  });

  group('stopping capture for Delete everything', () {
    test('copies are not kept while stopped, and are again after resume', () {
      service.stopCapture();
      source.copy('while stopped');
      expect(store.count, 0);
      service.resumeCapture();
      source.copy('after');
      expect(service.items.map((i) => i.preview), ['after']);
    });

    test('close without saving waiting copies writes nothing', () async {
      source.copy('saved');
      service.stopCapture();
      source.copy('late');
      await service.close(saveWaiting: false);
      final again = SqliteHistoryStore.open(
        path: '${dir.path}/kusunga.db',
        keyHex: _key,
      );
      expect(again.list().map((i) => i.preview), ['saved']);
      again.close();
    });
  });
}

class _CompactSpy extends FlakyStore {
  _CompactSpy(super.inner);
  int compacts = 0;
  bool failCompact = false;

  @override
  void compact() {
    if (failCompact) throw const FileSystemException('disk');
    compacts++;
    inner.compact();
  }
}
