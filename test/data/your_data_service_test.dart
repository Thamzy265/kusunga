// M1.8 Your data service: export to the file the user picks, import from
// one, and the round trip (AC1). File dialogs are a fake port; files are
// real temp files.
import 'dart:convert';
import 'dart:io';

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

class FakeFilePort implements FilePort {
  String? savePath;
  String? openPath;
  String? suggested;
  int saves = 0;
  int opens = 0;

  @override
  Future<String?> pickSavePath(String suggestedName) async {
    saves++;
    suggested = suggestedName;
    return savePath;
  }

  @override
  Future<String?> pickOpenPath() async {
    opens++;
    return openPath;
  }
}

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

    test('when the temp file next to it cannot be made (the Mac sandbox '
        'allows only the picked file), it writes the file directly', () {
      final path = p.join(dir.path, 'out.json');
      Directory('$path.kusunga-tmp').createSync();
      writeExportFile(path, utf8.encode('data'));
      expect(File(path).readAsStringSync(), 'data');
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
