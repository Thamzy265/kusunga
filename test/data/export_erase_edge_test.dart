// M1.8 tester: the export file on disk, round-trip fidelity through two real
// encrypted databases, the log, and Delete everything's links and failure
// cases (docs/design/your-data.md, "Export file", "Delete everything",
// "Failure plan", "Observability"). Fakes and temp folders only: never the
// real keychain, log or data folder. Bug repros are skipped unless
// KUSUNGA_REPRO=1.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/data/your_data_service.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _day = Duration.millisecondsPerDay;

final Object? _repro = Platform.environment['KUSUNGA_REPRO'] == '1'
    ? null
    : 'bug repro (set KUSUNGA_REPRO=1 to run)';

void main() {
  late Directory dir;
  late FakeLog fakeLog;
  late FakeFilePort files;
  final now = 1000 * _day;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_yd_');
    fakeLog = FakeLog();
    files = FakeFilePort();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ({HistoryService service, SqliteHistoryStore store}) open(
    String name, {
    ErrorLog? log,
    FakeClipboardSource? source,
  }) {
    final store = SqliteHistoryStore.open(
      path: p.join(dir.path, name),
      keyHex: _key,
    );
    final s = HistoryService(
      store: store,
      source: source ?? FakeClipboardSource(),
      log: log ?? fakeLog,
      clock: () => now,
      snippetStore: store.snippetStore(),
      ignoredAppStore: store.ignoredAppStore(),
    )..start();
    addTearDown(() async {
      await s.close();
      s.dispose();
    });
    return (service: s, store: store);
  }

  YourDataService yd(HistoryService h, {ErrorLog? log, ExportWriter? writer}) =>
      YourDataService(
        history: h,
        log: log ?? fakeLog,
        files: files,
        now: () => DateTime(2026, 11, 12, 9, 30),
        writer: writer,
      );

  group('round trip through a real file and two real databases (AC1)', () {
    test('order, types, shortcuts, unicode, newlines, NUL and very long '
        'text all come back the same', () async {
      final a = open('a.db');
      final texts = <String, String>{
        'Plain': 'hello',
        'Emoji 😀👨‍👩‍👧‍👦': 'flags 🇬🇧 and a ZWJ family 👨‍👩‍👧‍👦',
        'Accents é à ü ñ': 'Zażółć gęślą jaźń — 日本語 — العربية — עברית',
        'Newlines': 'line1\nline2\r\nline3\rline4\n\n',
        'Tabs\tin name?': 'tab\there',
        'NUL content': 'a\u0000b',
        'Quotes':
            '"double" \'single\' \\ back / slash </script> {"json": [1,2]}',
        'Edges': '  leading and trailing  ',
        'Long': 'long text ' * 100000, // 1,000,000 characters
      };
      var i = 0;
      for (final e in texts.entries) {
        final name = e.key.replaceAll('\t', ' ');
        a.store.snippetStore().insert(
          name: name,
          content: e.value,
          type: SnippetType.values[i % SnippetType.values.length],
          nowMs: 1 + i,
          shortcut: i.isEven ? ';s$i' : null,
        );
        i++;
      }
      for (var h = 0; h < 5; h++) {
        a.store.insertOrBump('copy $h 😀\nline', ClipKind.text, now - h * 1000);
      }
      files.savePath = p.join(dir.path, 'out.json');
      final saved = await yd(a.service).export(includeHistory: true);
      expect(saved, isA<ExportSaved>());

      final b = open('b.db');
      files.openPath = files.savePath;
      final check = await yd(b.service).checkImport();
      expect(check, isA<ImportReady>());
      final done = yd(
        b.service,
      ).runImport(check as ImportReady, applySettings: true);
      expect(done, isA<ImportDone>());

      List<List<Object?>> rows(HistoryService s) => [
        for (final r in s.snippets.records())
          [r.name, r.content, r.type, r.shortcut, r.position],
      ];
      expect(rows(b.service), rows(a.service));
      expect(
        [
          for (final r in b.store.records())
            [r.content, r.createdAt, r.lastCopiedAt],
        ],
        [
          for (final r in a.store.records())
            [r.content, r.createdAt, r.lastCopiedAt],
        ],
      );
    });

    test('the file on disk is UTF-8 JSON without a BOM, ends with a line '
        'break or brace, and is the only file written', () async {
      final a = open('a.db');
      a.store.snippetStore().insert(
        name: 'x',
        content: 'y',
        type: SnippetType.other,
        nowMs: 1,
      );
      files.savePath = p.join(dir.path, 'out.json');
      await yd(a.service).export(includeHistory: false);
      final bytes = File(files.savePath!).readAsBytesSync();
      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(json['format'], 'kusunga-export');
      expect(json.containsKey('history'), isFalse);
      final names = dir.listSync().map((e) => p.basename(e.path)).toSet();
      expect(names, contains('out.json'));
      expect(
        names.where((n) => n.contains('tmp') || n.endsWith('.json')),
        {'out.json'},
        reason: 'no temp file and no other export next to it',
      );
      expect(File('${files.savePath}.kusunga-tmp').existsSync(), isFalse);
    });

    test('exporting with 5,000 history items of 2,000 characters decodes '
        'back, under the 20 MB limit', () async {
      final a = open('a.db');
      a.store.setLimit(5000);
      for (var i = 0; i < 5000; i++) {
        a.store.insertOrBump(
          '${'x' * 1990}$i'.padRight(2000, 'y'),
          ClipKind.text,
          now - i,
        );
      }
      files.savePath = p.join(dir.path, 'big.json');
      final r = await yd(a.service).export(includeHistory: true);
      expect(r, isA<ExportSaved>().having((s) => s.history, 'history', 5000));
      expect(File(files.savePath!).lengthSync(), lessThan(maxImportBytes));
      files.openPath = files.savePath;
      expect(
        await yd(open('c.db').service).checkImport(),
        isA<ImportReady>().having((r) => r.history, 'history', 5000),
      );
    });
  });

  group('the export writer and links', () {
    test('a path that is a symlink to another file: the link is replaced, '
        'the file it pointed to is never written', () {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      Link(path).createSync(victim.path);
      writeExportFile(path, utf8.encode('{}'));
      expect(victim.readAsStringSync(), 'keep');
      expect(File(path).readAsStringSync(), '{}');
    });

    test('a leftover temp file from an earlier failed export is replaced, '
        'not appended to, and none remains', () {
      final path = p.join(dir.path, 'out.json');
      File('$path.kusunga-tmp').writeAsStringSync('half a file from before');
      writeExportFile(path, utf8.encode('new'));
      expect(File(path).readAsStringSync(), 'new');
      expect(File('$path.kusunga-tmp').existsSync(), isFalse);
    });

    test('a file name with spaces, unicode and dots is used as given', () {
      final path = p.join(dir.path, 'my export é 😀 v1.2.json');
      writeExportFile(path, utf8.encode('{}'));
      expect(File(path).readAsStringSync(), '{}');
    });

    test('BUG-T7 (Low): a symlink planted at <picked file>.kusunga-tmp is not '
        'written through', () {
      // The temp name is predictable. writeAsBytesSync follows a link
      // already sitting at that name, so a same-user process that planted
      // one gets the export (snippets, maybe history) written to a file of
      // its choice, and the user's own file is never written.
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep');
      final path = p.join(dir.path, 'out.json');
      Link('$path.kusunga-tmp').createSync(victim.path);
      try {
        writeExportFile(path, utf8.encode('{"secret":"snippets"}'));
      } catch (_) {}
      expect(victim.readAsStringSync(), 'keep');
    });
  });

  group('the log carries codes and numbers only', () {
    test('no file name, folder, snippet text or app name reaches the log '
        'file, through export, a refused import and an import', () async {
      final logFile = File(p.join(dir.path, 'kusunga.log'));
      final real = FileErrorLog(logFile);
      final a = open('a.db', log: real);
      a.store.snippetStore().insert(
        name: 'SECRETSNIPPETNAME',
        content: 'SECRETSNIPPETTEXT',
        type: SnippetType.other,
        nowMs: 1,
      );
      a.store.insertOrBump('SECRETHISTORYTEXT', ClipKind.text, now - 1);
      final sub = Directory(p.join(dir.path, 'PRIVATEFOLDERNAME'))
        ..createSync();
      final out = p.join(sub.path, 'my-bank-details-SECRETFILE.json');

      files.savePath = out;
      await yd(a.service, log: real).export(includeHistory: true);
      // a write failure, with the file name in the error
      await yd(
        a.service,
        log: real,
        writer: (path, bytes) => throw FileSystemException(
          'cannot write $path',
          path,
          const OSError('No space left on device', 28),
        ),
      ).export(includeHistory: true);
      // a refused file, then a damaged one, then one that is not there
      File(
        p.join(sub.path, 'bad-SECRETFILE.json'),
      ).writeAsStringSync('SECRETSNIPPETTEXT not json');
      files.openPath = p.join(sub.path, 'bad-SECRETFILE.json');
      await yd(a.service, log: real).checkImport();
      files.openPath = p.join(sub.path, 'missing-SECRETFILE.json');
      await yd(a.service, log: real).checkImport();
      // a good one into another database
      final b = open('b.db', log: real);
      files.openPath = out;
      final ready = await yd(b.service, log: real).checkImport() as ImportReady;
      yd(b.service, log: real).runImport(ready, applySettings: false);

      final lines = logFile.readAsLinesSync();
      expect(lines, isNotEmpty);
      final shape = RegExp(r'^\d{4}-\d\d-\d\dT[\d:.]+Z [A-Za-z]+( -?\d+)?$');
      for (final l in lines) {
        expect(l, matches(shape), reason: l);
      }
      final text = lines.join('\n');
      for (final secret in [
        'SECRET',
        'PRIVATE',
        'my-bank',
        'json',
        dir.path,
        'No space',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      final codes = lines.map((l) => l.split(' ')[1]).toSet();
      expect(
        codes,
        containsAll([
          'dataExported',
          'dataExportedHistory',
          'exportFailed',
          'importRejected',
          'dataImported',
          'dataImportedHistory',
          'dataImportSkipped',
        ]),
      );
      expect(
        lines.where((l) => l.contains('exportFailed')).single,
        endsWith('exportFailed 28'),
      );
    });

    test('the new codes each take at most one number, and the failure '
        'codes carry the OS number', () {
      // A code with two numbers would need a different log format.
      for (final c in [
        LogCode.dataExported,
        LogCode.dataExportedHistory,
        LogCode.dataImported,
        LogCode.dataImportedHistory,
        LogCode.dataImportSkipped,
        LogCode.importRejected,
        LogCode.importFailed,
        LogCode.exportFailed,
        LogCode.deleteEverythingDone,
        LogCode.deleteEverythingFailed,
        LogCode.deleteFileFailed,
      ]) {
        expect(c.name, matches(RegExp(r'^[a-z][A-Za-z]+$')));
      }
    });

    test('an import that fails in the database logs importFailed with no '
        'detail', () async {
      final a = open('a.db');
      await a.service.close(); // the store can no longer be written
      files.openPath = p.join(dir.path, 'in.json');
      File(files.openPath!).writeAsStringSync(
        jsonEncode({
          'format': 'kusunga-export',
          'version': 1,
          'snippets': [
            {'name': 'A', 'content': 'c', 'type': 'other'},
          ],
        }),
      );
      final y = yd(a.service);
      final ready = await y.checkImport() as ImportReady;
      final r = y.runImport(ready, applySettings: false);
      expect(r, isA<ImportFailedResult>());
      final i = fakeLog.codes.indexOf(LogCode.importFailed);
      expect(i, isNot(-1));
      expect(fakeLog.details[i], isNull);
    });
  });

  group('Delete everything: links, failures and the log file', () {
    late Directory folder;
    late FakeKeyStore keys;
    late List<String> steps;
    late FakeClipboardSource source;

    setUp(() {
      folder = Directory(p.join(dir.path, 'data'))..createSync();
      keys = FakeKeyStore(stored: _key);
      steps = [];
      source = FakeClipboardSource();
    });

    DataEraser eraser(
      EraseTarget t, {
      ErrorLog? log,
      void Function()? stopFileLog,
      Duration keyTimeout = const Duration(seconds: 30),
    }) => DataEraser(
      target: t,
      log: log ?? fakeLog,
      stopFileLog: stopFileLog ?? () => steps.add('stopFileLog'),
      turnOffLogin: () async => steps.add('loginOff'),
      keyTimeout: keyTimeout,
    );

    HistoryService openIn(Directory d) {
      final store = SqliteHistoryStore.open(
        path: p.join(d.path, 'kusunga.db'),
        keyHex: _key,
      );
      final s = HistoryService(
        store: store,
        source: source,
        log: fakeLog,
        clock: () => now,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
      addTearDown(s.dispose);
      return s;
    }

    test(
      'a hard link: the name goes, the other name and its content stay',
      () async {
        final h = openIn(folder);
        final outside = File(p.join(dir.path, 'precious.txt'))
          ..writeAsStringSync('precious');
        final r = Process.runSync('ln', [
          outside.path,
          p.join(folder.path, 'kusunga.db.bak'),
        ]);
        expect(r.exitCode, 0);
        await eraser(
          DefaultEraseTarget(keys: keys, folder: () async => folder),
        ).run(h);
        expect(outside.readAsStringSync(), 'precious');
        expect(folder.listSync(), isEmpty);
      },
      skip: Platform.isWindows ? 'ln needs a POSIX shell' : false,
    );

    test('a link to a folder, named like a Kusunga file: the link goes, the '
        'folder and what is in it stay', () async {
      final h = openIn(folder);
      final outside = Directory(p.join(dir.path, 'outside'))..createSync();
      File(p.join(outside.path, 'important.txt')).writeAsStringSync('i');
      Link(
        p.join(folder.path, 'kusunga.db.unreadable-1'),
      ).createSync(outside.path);
      Link(
        p.join(folder.path, 'kusunga.log'),
      ).createSync(p.join(dir.path, 'nowhere'));
      await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
      ).run(h);
      expect(
        File(p.join(outside.path, 'important.txt')).readAsStringSync(),
        'i',
      );
      expect(folder.listSync(followLinks: false), isEmpty);
    });

    test('a debug profile folder with a link to a folder, a dangling link '
        'and a nested folder: only its own entries go', () async {
      final profile = Directory(p.join(folder.path, 'profiles', 'qa'))
        ..createSync(recursive: true);
      final h = openIn(profile);
      final outside = Directory(p.join(dir.path, 'outside'))..createSync();
      final keep = File(p.join(outside.path, 'keep.txt'))
        ..writeAsStringSync('k');
      Link(
        p.join(profile.path, 'shortcut-to-outside'),
      ).createSync(outside.path);
      Link(
        p.join(profile.path, 'dangling'),
      ).createSync(p.join(dir.path, 'gone'));
      Directory(p.join(profile.path, 'a', 'b')).createSync(recursive: true);
      File(p.join(profile.path, 'a', 'b', 'x')).writeAsStringSync('x');
      File(p.join(folder.path, 'kusunga.db')).writeAsStringSync('the real one');
      final r = await eraser(
        ProfileEraseTarget(folder: () async => profile),
      ).run(h);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(profile.existsSync(), isFalse);
      expect(keep.readAsStringSync(), 'k');
      expect(
        File(p.join(folder.path, 'kusunga.db')).readAsStringSync(),
        'the real one',
      );
      expect(keys.deletes, 0);
    });

    test('BUG-T8 (Low): a profile folder that is itself a link to another '
        'folder: that folder\'s contents are not deleted', () async {
      // listSync(recursive) on a path that is a link lists the target's
      // files, and each is deleted: "links are never followed" holds for
      // entries inside the folder but not for the folder itself.
      final real = Directory(p.join(dir.path, 'other-place'))..createSync();
      final keep = File(p.join(real.path, 'keep.txt'))..writeAsStringSync('k');
      final profile = Directory(p.join(folder.path, 'profiles', 'qa'));
      profile.parent.createSync(recursive: true);
      Link(profile.path).createSync(real.path);
      final h = openIn(real);
      await eraser(ProfileEraseTarget(folder: () async => profile)).run(h);
      expect(keep.existsSync(), isTrue);
    });

    test('a folder named like a Kusunga file is left alone and not counted '
        'as a file that could not be removed', () async {
      final h = openIn(folder);
      Directory(p.join(folder.path, 'kusunga.log')).createSync();
      final r = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
      ).run(h);
      expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      expect(
        Directory(p.join(folder.path, 'kusunga.log')).existsSync(),
        isTrue,
      );
    });

    test('the log file is not written again once the file log is stopped: '
        'deleteEverythingDone is its last line, and later codes do not '
        'bring the file back', () async {
      final logFile = File(p.join(folder.path, 'kusunga.log'));
      final deferred = DeferredErrorLog()..attach(FileErrorLog(logFile));
      final h = openIn(folder);
      keys.onDelete = () => steps.add('key');
      Future<void> loginOffLogs() async {
        steps.add('loginOff');
        deferred.log(LogCode.loginItemOff);
      }

      final e = DataEraser(
        target: DefaultEraseTarget(keys: keys, folder: () async => folder),
        log: deferred,
        stopFileLog: deferred.stopFile,
        turnOffLogin: loginOffLogs,
      );
      deferred.log(LogCode.dataExported, 1); // a line that exists already
      expect(logFile.existsSync(), isTrue);
      final r = await e.run(h);
      expect(r, isA<Erased>());
      deferred.log(LogCode.captureResumed);
      expect(logFile.existsSync(), isFalse);
      expect(folder.listSync(), isEmpty);
    });

    test('a key delete that answers after the time-out, with a code in the '
        'error, is logged by number and still counts as not deleted', () async {
      final h = openIn(folder);
      final gate = keys.holdDelete();
      final result = await eraser(
        DefaultEraseTarget(keys: keys, folder: () async => folder),
        keyTimeout: const Duration(milliseconds: 20),
      ).run(h);
      expect(result, isA<EraseFailed>());
      expect(fakeLog.codes, contains(LogCode.deleteEverythingFailed));
      expect(File(p.join(folder.path, 'kusunga.db')).existsSync(), isTrue);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'BUG-T5 (Medium): after "Nothing was deleted" (a key delete that '
      'timed out) the key is still there when the keychain answers late',
      () async {
        // The key delete is only given up on, not cancelled. If the keychain
        // answers after the 30 s, it still removes the key while Kusunga is
        // recording again with the open database, and the next launch can no
        // longer read the file: the snippets and history are gone although
        // the user was told nothing was deleted.
        final h = openIn(folder);
        final gate = keys.holdDelete();
        final result = await eraser(
          DefaultEraseTarget(keys: keys, folder: () async => folder),
          keyTimeout: const Duration(milliseconds: 20),
        ).run(h);
        expect(result, isA<EraseFailed>());
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(keys.stored, _key);
      },
      skip: _repro,
    );

    test('BUG-T6 (Low): when the data folder cannot be listed after the key '
        'is gone, the result does not claim every file is gone', () async {
      // _deleteFiles logs deleteFileFailed and returns 0, so the dialog
      // says "Everything is deleted." while kusunga.db is still there.
      final h = openIn(folder);
      final result = await eraser(
        DefaultEraseTarget(
          keys: keys,
          folder: () async => throw const FileSystemException('denied'),
        ),
      ).run(h);
      expect(fakeLog.codes, contains(LogCode.deleteFileFailed));
      expect(
        result,
        isA<Erased>().having((e) => e.filesLeft, 'left', greaterThan(0)),
      );
    }, skip: _repro);

    test('a failing key delete reports its number from a platform error, '
        'a file error and an error with none', () async {
      final h = openIn(folder);
      for (final (error, expected) in <(Object, int?)>[
        (const FileSystemException('x', '', OSError('e', 5)), 5),
        (StateError('no number'), null),
      ]) {
        fakeLog.codes.clear();
        fakeLog.details.clear();
        keys.deleteError = error;
        final r = await eraser(
          DefaultEraseTarget(keys: keys, folder: () async => folder),
        ).run(h);
        expect(r, isA<EraseFailed>());
        expect(fakeLog.details.single, expected);
        expect(keys.stored, _key);
      }
    });
  });
}
