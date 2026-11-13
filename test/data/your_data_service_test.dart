// M1.8 Your data service: export to the file the user picks, import from
// one, and the round trip (AC1). File dialogs are a fake port; files are
// real temp files.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/data/your_data_service.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _day = Duration.millisecondsPerDay;

void main() {
  late Directory dir;
  late FakeLog log;
  late FakeFilePort files;
  final now = 1000 * _day;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_yds_');
    log = FakeLog();
    files = FakeFilePort();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryService history(String name) {
    final store = SqliteHistoryStore.open(
      path: p.join(dir.path, name),
      keyHex: _key,
    );
    final s = HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: log,
      clock: () => now,
      snippetStore: store.snippetStore(),
      ignoredAppStore: store.ignoredAppStore(),
    )..start();
    addTearDown(() async {
      await s.close();
      s.dispose();
    });
    return s;
  }

  YourDataService service(HistoryService h, {ExportWriter? writer}) =>
      YourDataService(
        history: h,
        log: log,
        files: files,
        now: () => DateTime(2026, 11, 12, 9, 30),
        writer: writer,
      );

  group('export', () {
    test(
      'suggests kusunga-export-YYYY-MM-DD.json and writes the file',
      () async {
        final h = history('a.db');
        h.snippets.save(name: 'Phone', content: '123', type: SnippetType.phone);
        files.savePath = p.join(dir.path, 'out.json');
        final r = await service(h).export(includeHistory: false);
        expect(files.suggested, 'kusunga-export-2026-11-12.json');
        expect(r, isA<ExportSaved>().having((e) => e.snippets, 'n', 1));
        final json =
            jsonDecode(File(files.savePath!).readAsStringSync()) as Map;
        expect(json['format'], 'kusunga-export');
        expect(json.containsKey('history'), isFalse);
        expect(log.codes, contains(LogCode.dataExported));
        expect(log.codes, isNot(contains(LogCode.dataExportedHistory)));
      },
    );

    test('cancelled save dialog: nothing written, nothing logged', () async {
      final h = history('a.db');
      final r = await service(h).export(includeHistory: true);
      expect(r, isA<ExportCancelled>());
      expect(dir.listSync().where((e) => e.path.endsWith('.json')), isEmpty);
      expect(log.codes, isEmpty);
    });

    test('a write that fails leaves no file and logs exportFailed with its '
        'number', () async {
      final h = history('a.db');
      files.savePath = p.join(dir.path, 'missing-folder', 'out.json');
      final r = await service(h).export(includeHistory: false);
      expect(r, isA<ExportFailed>());
      expect(File(files.savePath!).existsSync(), isFalse);
      expect(log.codes, contains(LogCode.exportFailed));
      expect(log.details[log.codes.indexOf(LogCode.exportFailed)], isNotNull);
    });

    test('history counts in the result and the log when included', () async {
      final h = history('a.db');
      h.importBundle(
        ExportBundle(
          snippets: const [],
          history: [
            ExportHistoryItem(
              content: 'x',
              kind: ClipKind.text,
              createdAt: now,
              lastCopiedAt: now,
            ),
          ],
        ),
        applySettings: false,
      );
      files.savePath = p.join(dir.path, 'out.json');
      final r = await service(h).export(includeHistory: true);
      expect(r, isA<ExportSaved>().having((e) => e.history, 'history', 1));
      final i = log.codes.indexOf(LogCode.dataExportedHistory);
      expect(log.details[i], 1);
    });
  });

  group('the export writer', () {
    test('replaces an existing file in one step; no temp file left', () {
      final path = p.join(dir.path, 'out.json');
      File(path).writeAsStringSync('old');
      writeExportFile(path, utf8.encode('new'));
      expect(File(path).readAsStringSync(), 'new');
      expect(dir.listSync().map((e) => p.basename(e.path)), ['out.json']);
    });

    /// A folder Kusunga may not add files to, with the picked file already
    /// in it: what the Mac sandbox allows.
    Directory sandboxLike(String picked, {void Function(String path)? plant}) {
      final box = Directory(p.join(dir.path, 'box'))..createSync();
      final path = p.join(box.path, picked);
      plant?.call(path);
      Process.runSync('chmod', ['555', box.path]);
      addTearDown(() => Process.runSync('chmod', ['755', box.path]));
      return box;
    }

    test('when the temp file next to it cannot be made (the Mac sandbox '
        'allows only the picked file), it writes the file directly', () {
      final box = sandboxLike(
        'out.json',
        plant: (path) => File(path).writeAsStringSync('old'),
      );
      final path = p.join(box.path, 'out.json');
      writeExportFile(path, utf8.encode('data'));
      expect(File(path).readAsStringSync(), 'data');
      expect(box.listSync().map((e) => p.basename(e.path)), ['out.json']);
    }, skip: Platform.isWindows ? 'chmod needs a POSIX system' : false);

    test('written directly, a picked path that is a link is refused: the file '
        'it points to is never written (T7)', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final box = sandboxLike(
        'out.json',
        plant: (path) => Link(path).createSync(victim.path),
      );
      expect(
        () => writeExportFile(p.join(box.path, 'out.json'), [1, 2, 3]),
        throwsA(isA<FileSystemException>()),
      );
      expect(victim.readAsStringSync(), 'keep');
    }, skip: Platform.isWindows ? 'chmod needs a POSIX system' : false);

    test('written directly, an existing file Kusunga cannot open for writing '
        'is left as it was, never removed (R3)', () {
      final path = p.join(dir.path, 'out.json');
      final keep = File(path)..writeAsStringSync('precious');
      // Something already at the temp name, so the temp file can't be
      // made and the file is written directly, as in the Mac sandbox.
      Directory(exportTempPath(path, Random(3))).createSync();
      Process.runSync('chmod', ['444', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      expect(
        () => writeExportFile(path, utf8.encode('{}'), random: Random(3)),
        throwsA(isA<FileSystemException>()),
      );
      expect(keep.existsSync(), isTrue);
      expect(keep.readAsStringSync(), 'precious');
    }, skip: Platform.isWindows ? 'chmod needs a POSIX system' : false);

    test('the temp name has 128 random bits, so it differs every time and '
        "can't be guessed (T7)", () {
      final path = p.join(dir.path, 'out.json');
      final a = exportTempPath(path);
      final b = exportTempPath(path);
      expect(a, isNot(b));
      expect(
        p.basename(a),
        matches(RegExp(r'^out\.json\.kusunga-tmp-[0-9a-f]{32}$')),
      );
    });

    test('a link already at the temp name is never written through: the '
        'temp file is made only if nothing is there (T7)', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final nowhere = p.join(dir.path, 'nowhere');
      for (final (name, target) in [
        ('a.json', victim.path),
        ('b.json', nowhere), // a link to nothing yet
      ]) {
        final path = p.join(dir.path, name);
        // The same random numbers, so the link sits at the exact temp name.
        Link(exportTempPath(path, Random(7))).createSync(target);
        writeExportFile(path, utf8.encode('{}'), random: Random(7));
        expect(File(path).readAsStringSync(), '{}');
      }
      expect(victim.readAsStringSync(), 'keep');
      expect(File(nowhere).existsSync(), isFalse);
    });

    test('temp files an earlier export to the same file left behind are '
        'removed; links, folders and other names are left alone', () {
      final path = p.join(dir.path, 'out.json');
      final crashed = File(exportTempPath(path))..writeAsStringSync('half');
      final older = File('$path.kusunga-tmp')..writeAsStringSync('half');
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final link = Link(exportTempPath(path))..createSync(victim.path);
      final folder = Directory(exportTempPath(path))..createSync();
      final notOurs = File('$path.kusunga-tmp-notes')..writeAsStringSync('n');
      final otherExport = File(exportTempPath(p.join(dir.path, 'b.json')))
        ..writeAsStringSync('b');
      writeExportFile(path, utf8.encode('new'));
      expect(File(path).readAsStringSync(), 'new');
      expect(crashed.existsSync(), isFalse);
      expect(older.existsSync(), isFalse);
      expect(link.existsSync(), isTrue);
      expect(victim.readAsStringSync(), 'keep');
      expect(folder.existsSync(), isTrue);
      expect(notOurs.existsSync(), isTrue);
      expect(otherExport.existsSync(), isTrue);
    });

    test('a failed write leaves no half file', () {
      final path = p.join(dir.path, 'nope', 'out.json');
      expect(
        () => writeExportFile(path, [1, 2, 3]),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).existsSync(), isFalse);
      expect(File('$path.kusunga-tmp').existsSync(), isFalse);
    });
  });

  group('import', () {
    test('cancelled open dialog: nothing happens', () async {
      final h = history('a.db');
      expect(await service(h).checkImport(), isA<ImportCancelled>());
      expect(log.codes, isEmpty);
    });

    test('a refused file is logged with its reason number only', () async {
      final h = history('a.db');
      files.openPath = p.join(dir.path, 'bad.json');
      File(files.openPath!).writeAsStringSync('{"format":"other"}');
      final r = await service(h).checkImport();
      expect(r, isA<ImportRefused>());
      final i = log.codes.indexOf(LogCode.importRejected);
      expect(log.details[i], ImportRejectReason.wrongFormat.number);
    });

    test('a file over 20 MB is refused without reading it all', () async {
      final h = history('a.db');
      files.openPath = p.join(dir.path, 'big.json');
      final raf = File(files.openPath!).openSync(mode: FileMode.write);
      raf.setPositionSync(maxImportBytes + 10);
      raf.writeByteSync(0x20);
      raf.closeSync();
      final r = await service(h).checkImport();
      expect(r, isA<ImportRefused>());
      final i = log.codes.indexOf(LogCode.importRejected);
      expect(log.details[i], ImportRejectReason.tooLarge.number);
    });

    group('the time rules (lead ruling 2026-11-12)', () {
      // The service's clock: 2026-11-12 09:30, local time.
      final importTime = DateTime(2026, 11, 12, 9, 30).millisecondsSinceEpoch;

      void writeFile(int created, int last) {
        files.openPath = p.join(dir.path, 'in.json');
        File(files.openPath!).writeAsStringSync(
          encodeExport(
            ExportBundle(
              snippets: const [],
              history: [
                ExportHistoryItem(
                  content: 'x',
                  kind: ClipKind.text,
                  createdAt: created,
                  lastCopiedAt: last,
                ),
              ],
            ),
            exportedAt: DateTime(2026),
          ),
        );
      }

      test('a history time more than 24 hours after the import refuses the '
          'file, logged as a bad item', () async {
        final h = history('a.db');
        writeFile(importTime, importTime + _day + 1000);
        expect(await service(h).checkImport(), isA<ImportRefused>());
        final i = log.codes.indexOf(LogCode.importRejected);
        expect(log.details[i], ImportRejectReason.badItem.number);
        writeFile(importTime, importTime + _day);
        expect(await service(h).checkImport(), isA<ImportReady>());
      });

      test('a last copy before its creation is stored with the creation set '
          'to the last copy', () async {
        final h = history('a.db');
        writeFile(now, now - 3 * _day);
        final s = service(h);
        final ready = await s.checkImport() as ImportReady;
        expect(s.runImport(ready, applySettings: false), isA<ImportDone>());
        final r = h.exportBundle(includeHistory: true).history!.single;
        expect(r.createdAt, now - 3 * _day);
        expect(r.lastCopiedAt, now - 3 * _day);
      });
    });

    test('a file that cannot be read is refused like a damaged one', () async {
      final h = history('a.db');
      files.openPath = p.join(dir.path, 'gone.json');
      expect(await service(h).checkImport(), isA<ImportRefused>());
    });

    test('ready: counts from the file (history only what will be added), the '
        'file name, and whether it has settings', () async {
      final h = history('a.db');
      files.openPath = p.join(dir.path, 'kusunga-export-2026-11-12.json');
      File(files.openPath!).writeAsStringSync(
        encodeExport(
          ExportBundle(
            snippets: const [
              ExportSnippet(
                name: 'A',
                content: 'a',
                type: SnippetType.other,
                position: 0,
              ),
            ],
            history: [
              ExportHistoryItem(
                content: 'old',
                kind: ClipKind.text,
                createdAt: 0,
                lastCopiedAt: now - 40 * _day,
              ),
              ExportHistoryItem(
                content: 'new',
                kind: ClipKind.text,
                createdAt: 0,
                lastCopiedAt: now,
              ),
            ],
            settings: const ExportSettings(historyLimit: 10),
          ),
          exportedAt: DateTime(2026),
        ),
      );
      final r = await service(h).checkImport() as ImportReady;
      expect(r.fileName, 'kusunga-export-2026-11-12.json');
      expect(r.snippets, 1);
      expect(r.history, 1);
      expect(r.hasSettings, isTrue);
      expect(r.isEmpty, isFalse);
    });

    test('ready: the history count is the rows the import will add, with '
        'and without the file\'s settings; the import adds exactly that '
        '(T4)', () async {
      final h = history('a.db');
      h.setLimit(10);
      for (var i = 0; i < 9; i++) {
        h.importBundle(
          ExportBundle(
            snippets: const [],
            history: [
              ExportHistoryItem(
                content: 'mine $i',
                kind: ClipKind.text,
                createdAt: 0,
                lastCopiedAt: now - i,
              ),
            ],
          ),
          applySettings: false,
        );
      }
      ExportHistoryItem item(String content, int last) => ExportHistoryItem(
        content: content,
        kind: ClipKind.text,
        createdAt: 0,
        lastCopiedAt: last,
      );
      files.openPath = p.join(dir.path, 'in.json');
      File(files.openPath!).writeAsStringSync(
        encodeExport(
          ExportBundle(
            snippets: const [],
            history: [
              item('dup', now - _day),
              item('dup', now - _day),
              item('mine 0', now - _day), // already here
              item('older', now - 2 * _day),
              item('oldest', now - 3 * _day),
            ],
            settings: const ExportSettings(historyLimit: 50),
          ),
          exportedAt: DateTime(2026),
        ),
      );
      final s = service(h);
      final r = await s.checkImport() as ImportReady;
      // Limit 10 with 9 here: one new row fits, the newest ("dup").
      expect(r.history, 1);
      expect(r.historyFor(applySettings: false), 1);
      // The file's limit of 50: "dup", "older" and "oldest".
      expect(r.historyFor(applySettings: true), 3);
      expect(h.items.length, 9, reason: 'checking changed nothing');
      final done = s.runImport(r, applySettings: true) as ImportDone;
      expect(done.counts.historyAdded, 3);
      expect(h.items.length, 12);
      final i = log.codes.indexOf(LogCode.dataImportedHistory);
      expect(log.details[i], 3);
    });

    test('ready: a file with only settings or ignored apps is not empty; it '
        'is settings only (R4)', () async {
      final h = history('a.db');
      for (final (bundle, settingsOnly) in [
        (const ExportBundle(snippets: []), false),
        (
          const ExportBundle(
            snippets: [],
            settings: ExportSettings(historyLimit: 300),
          ),
          true,
        ),
        (
          const ExportBundle(
            snippets: [],
            ignoredApps: [IgnoredApp('com.example.vault', 'Vault')],
          ),
          true,
        ),
      ]) {
        files.openPath = p.join(dir.path, 'in.json');
        File(
          files.openPath!,
        ).writeAsStringSync(encodeExport(bundle, exportedAt: DateTime(2026)));
        final r = await service(h).checkImport() as ImportReady;
        expect(r.settingsOnly, settingsOnly);
        expect(r.isEmpty, !settingsOnly);
      }
    });

    test('ready: nothing to import only when no snippet and no history row '
        'would be added either way (T4)', () async {
      final h = history('a.db');
      h.importBundle(
        ExportBundle(
          snippets: const [],
          history: [
            ExportHistoryItem(
              content: 'here',
              kind: ClipKind.text,
              createdAt: 0,
              lastCopiedAt: now,
            ),
          ],
        ),
        applySettings: false,
      );
      files.openPath = p.join(dir.path, 'in.json');
      File(files.openPath!).writeAsStringSync(
        encodeExport(
          ExportBundle(
            snippets: const [],
            history: [
              ExportHistoryItem(
                content: 'here',
                kind: ClipKind.text,
                createdAt: 0,
                lastCopiedAt: now,
              ),
            ],
          ),
          exportedAt: DateTime(2026),
        ),
      );
      final r = await service(h).checkImport() as ImportReady;
      expect(r.history, 0);
      expect(r.isEmpty, isTrue);
    });

    test('a committed import is reported as done, with the new limit in '
        'use, even where a read of the limit after the commit would fail '
        '(R6)', () async {
      // The seam stands for a settings read that fails once the import's
      // transaction has committed; inside it, the read works.
      var readsInside = 0;
      final store = SqliteHistoryStore.open(
        path: p.join(dir.path, 'seam.db'),
        keyHex: _key,
        onImportLimitRead: ({required inTransaction}) {
          if (!inTransaction) {
            throw const FileSystemException('read after the commit failed');
          }
          readsInside++;
        },
      );
      final h = HistoryService(
        store: store,
        source: FakeClipboardSource(),
        log: log,
        clock: () => now,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
      addTearDown(() async {
        await h.close();
        h.dispose();
      });
      files.openPath = p.join(dir.path, 'in.json');
      File(files.openPath!).writeAsStringSync(
        encodeExport(
          const ExportBundle(
            snippets: [
              ExportSnippet(
                name: 'A',
                content: 'a',
                type: SnippetType.other,
                position: 0,
              ),
            ],
            settings: ExportSettings(historyLimit: 300),
          ),
          exportedAt: DateTime(2026),
        ),
      );
      final s = service(h);
      final ready = await s.checkImport() as ImportReady;
      final r = s.runImport(ready, applySettings: true);
      expect(r, isA<ImportDone>(), reason: 'committed, so reported as done');
      expect(log.codes, isNot(contains(LogCode.importFailed)));
      expect(store.limit, 300, reason: 'the cached limit in use');
      expect(h.limit, 300);
      expect(h.snippets.items.single.name, 'A');
      expect(readsInside, greaterThan(0));
    });

    test(
      'a write failure is logged as importFailed and changes nothing',
      () async {
        final h = history('a.db');
        final s = service(h);
        final ready = ImportReady(
          bundle: const ExportBundle(
            snippets: [
              ExportSnippet(
                name: 'A',
                content: 'a',
                type: SnippetType.other,
                position: 0,
              ),
            ],
          ),
          fileName: 'f.json',
          snippets: 1,
          history: 0,
        );
        await h.close();
        expect(
          s.runImport(ready, applySettings: false),
          isA<ImportFailedResult>(),
        );
        expect(log.codes, contains(LogCode.importFailed));
      },
    );
  });

  test('round trip (AC1): export then import gives the same data', () async {
    final a = history('a.db');
    a.snippets.save(
      name: 'Phone',
      content: '+44 1',
      type: SnippetType.phone,
      shortcut: ';ph',
    );
    a.snippets.save(
      name: 'Bank',
      content: 'IBAN GB00 0000\nline 2',
      type: SnippetType.other,
    );
    a.snippets.save(
      name: 'Site',
      content: 'https://example.com',
      type: SnippetType.link,
      shortcut: ';site',
    );
    a.importBundle(
      ExportBundle(
        snippets: const [],
        history: [
          for (var i = 0; i < 5; i++)
            ExportHistoryItem(
              content: 'item $i ${'é' * i}',
              kind: i.isEven ? ClipKind.text : ClipKind.link,
              createdAt: now - (10 - i) * 1000,
              lastCopiedAt: now - (5 - i) * 1000,
            ),
        ],
      ),
      applySettings: false,
    );
    a.setLimit(300);
    a.expiry.setDays(7);
    a.saveSetting('typed_shortcuts_on', '1');
    a.saveSetting('paste_mode', 'copy_only');
    a.ignoredApps.add(const IgnoredApp('com.example.vault', 'Vault'));
    files.savePath = p.join(dir.path, 'export.json');
    expect(await service(a).export(includeHistory: true), isA<ExportSaved>());

    final b = history('b.db');
    b.ignoredApps.remove('com.bitwarden.desktop');
    files.openPath = files.savePath;
    final sb = service(b);
    final ready = await sb.checkImport() as ImportReady;
    final done = sb.runImport(ready, applySettings: true) as ImportDone;
    expect(done.counts.snippetsAdded, 3);
    expect(done.counts.historyAdded, 5);

    final ea = a.exportBundle(includeHistory: true);
    final eb = b.exportBundle(includeHistory: true);
    String snippets(ExportBundle e) => [
      for (final s in e.snippets)
        '${s.position}|${s.name}|${s.content}|${s.type.name}|${s.shortcut}',
    ].join('\n');
    String hist(ExportBundle e) => [
      for (final h in e.history!)
        '${h.content}|${h.kind.name}|${h.createdAt}|${h.lastCopiedAt}',
    ].join('\n');
    expect(snippets(eb), snippets(ea));
    expect(hist(eb), hist(ea));
    expect(eb.settings!.historyLimit, 300);
    expect(eb.settings!.historyExpiryDays, 7);
    expect(eb.settings!.typedShortcutsOn, isTrue);
    expect(eb.settings!.pasteMode, 'copy_only');
    expect(
      eb.ignoredApps!.map((a) => a.appId).toSet(),
      ea.ignoredApps!.map((a) => a.appId).toSet(),
      reason: 'the removed preset came back, the extra app was added',
    );

    // Importing the same file again adds nothing new.
    final again =
        sb.runImport(
              await sb.checkImport() as ImportReady,
              applySettings: false,
            )
            as ImportDone;
    expect(again.counts.snippetsAdded, 0);
    expect(again.counts.snippetsAlreadyHere, 3);
    expect(b.snippets.items.length, 3);
    expect(b.items.length, 5);
  });
}
