// M1.8 tester, round 2 re-check: R3 (a direct export write never removes a
// file it could not open), R5 (export capped at 5,000 items, newest first),
// R7a/R7b (the partial-delete claim and Windows error numbers). Temp folders
// and fakes only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/data/your_data_service.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/history/windows_key_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../support/close_service.dart';
import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_tester_r2_'));
  tearDown(() {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
    }
    dir.deleteSync(recursive: true);
  });

  group('R3: the picked file is kept when it cannot be opened', () {
    // A folder that takes no new files makes the temp file impossible, so
    // the write goes straight to the picked file (the Mac sandbox case).
    Directory lockedFolder() {
      final d = Directory(p.join(dir.path, 'locked'))..createSync();
      return d;
    }

    test('a read-only file: the export fails and the file and its content '
        'are exactly as they were', () {
      final d = lockedFolder();
      final f = File(p.join(d.path, 'old.json'))..writeAsStringSync('mine');
      Process.runSync('chmod', ['444', f.path]);
      Process.runSync('chmod', ['500', d.path]);
      expect(
        () => writeExportFile(f.path, utf8.encode('new')),
        throwsA(isA<FileSystemException>()),
      );
      expect(f.existsSync(), isTrue);
      expect(f.readAsStringSync(), 'mine');
    }, skip: Platform.isWindows);

    test('a file with no rights at all: kept', () {
      final d = lockedFolder();
      final f = File(p.join(d.path, 'old.json'))..writeAsStringSync('mine');
      Process.runSync('chmod', ['000', f.path]);
      Process.runSync('chmod', ['500', d.path]);
      expect(
        () => writeExportFile(f.path, utf8.encode('new')),
        throwsA(isA<FileSystemException>()),
      );
      Process.runSync('chmod', ['600', f.path]);
      expect(f.readAsStringSync(), 'mine');
    }, skip: Platform.isWindows);

    test('a writable file in such a folder is written in place, whole', () {
      final d = lockedFolder();
      final f = File(p.join(d.path, 'old.json'))
        ..writeAsStringSync('a much longer old export, ' * 100);
      Process.runSync('chmod', ['500', d.path]);
      writeExportFile(f.path, utf8.encode('short'));
      expect(f.readAsStringSync(), 'short');
    }, skip: Platform.isWindows);

    test('a name that does not exist in such a folder: the export fails and '
        'nothing is made', () {
      final d = lockedFolder();
      Process.runSync('chmod', ['500', d.path]);
      expect(
        () => writeExportFile(p.join(d.path, 'new.json'), utf8.encode('x')),
        throwsA(isA<FileSystemException>()),
      );
      expect(d.listSync(), isEmpty);
    }, skip: Platform.isWindows);

    test('the service reports a read-only target as a failed export with '
        'its number logged, and keeps the file', () async {
      final d = lockedFolder();
      final f = File(p.join(d.path, 'old.json'))..writeAsStringSync('mine');
      Process.runSync('chmod', ['444', f.path]);
      Process.runSync('chmod', ['500', d.path]);
      final log = FakeLog();
      final files = FakeFilePort()..savePath = f.path;
      final service = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: log,
      )..start();
      addCloseTearDown(service);
      final r = await YourDataService(
        history: service,
        log: log,
        files: files,
      ).export(includeHistory: false);
      expect(r, isA<ExportFailed>());
      expect(log.codes, contains(LogCode.exportFailed));
      expect(f.readAsStringSync(), 'mine');
    }, skip: Platform.isWindows);
  });

  group('R5: the export is capped at 5,000 items, newest first', () {
    test('5,000 stored plus waiting copies: the file has 5,000, the waiting '
        'ones first, the oldest stored ones left out, and it reads back', () {
      final inner = MemoryHistoryStore();
      final store = FlakyStore(inner)..failWrites = false;
      inner.setLimit(5000);
      for (var i = 0; i < 5000; i++) {
        inner.insertOrBump('old $i', ClipKind.text, 1000 + i);
      }
      var now = 10000000;
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: FakeLog(),
        clock: () => now++,
      )..start();
      addCloseTearDown(service);
      store.failWrites = true; // new copies wait in memory
      source.copy('waiting 1');
      source.copy('waiting 2');
      source.copy('waiting 3');
      final b = service.exportBundle(includeHistory: true);
      expect(b.history, hasLength(5000));
      expect(b.history!.first.content, 'waiting 3');
      expect(b.history!.take(3).map((h) => h.content), [
        'waiting 3',
        'waiting 2',
        'waiting 1',
      ]);
      final times = b.history!.map((h) => h.lastCopiedAt).toList();
      expect(times, [...times]..sort((a, c) => c.compareTo(a)));
      expect(b.history!.map((h) => h.content), isNot(contains('old 0')));
      expect(b.history!.map((h) => h.content), isNot(contains('old 2')));
      expect(b.history!.map((h) => h.content), contains('old 3'));
      final text = encodeExport(b, exportedAt: DateTime.utc(2026, 11, 12));
      expect(
        decodeImport(utf8.encode(text)).history,
        hasLength(5000),
        reason: 'what is exported can always be imported',
      );
    });

    test('4,999 stored and 1 waiting: all 5,000 are written', () {
      final inner = MemoryHistoryStore()..setLimit(5000);
      for (var i = 0; i < 4999; i++) {
        inner.insertOrBump('old $i', ClipKind.text, 1000 + i);
      }
      final store = FlakyStore(inner);
      final source = FakeClipboardSource();
      final service = HistoryService(
        store: store,
        source: source,
        log: FakeLog(),
        clock: () => 10000000,
      )..start();
      addCloseTearDown(service);
      store.failWrites = true;
      source.copy('waiting');
      expect(
        service.exportBundle(includeHistory: true).history,
        hasLength(5000),
      );
    });

    test('the export never includes history when it was not asked for, '
        'whatever the count', () {
      final service = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: FakeLog(),
      )..start();
      addCloseTearDown(service);
      expect(service.exportBundle(includeHistory: false).history, isNull);
      expect(HistoryStore.maxLimit, 5000);
    });
  });

  group('R7b: Windows error numbers in the log', () {
    test('an HRESULT made from a Win32 error gives the Win32 number; any '
        'other HRESULT is logged as it is', () {
      expect(win32ErrorNumber(0x80070005), 5);
      expect(win32ErrorNumber(0x80070520), 1312);
      expect(win32ErrorNumber(0x8007FFFF), 0xFFFF);
      expect(win32ErrorNumber(0x80070000), 0);
      expect(win32ErrorNumber(0x80004005), 0x80004005);
      expect(win32ErrorNumber(0x80090005), 0x80090005);
      expect(win32ErrorNumber(5), 5);
      expect(win32ErrorNumber(0), 0);
    });

    test(
      'a refused key delete logs the number and nothing of the message',
      () async {
        final log = FakeLog();
        final keys = FakeKeyStore(stored: _key)
          ..deleteError = WindowsException(ERROR_ACCESS_DENIED.toHRESULT());
        final store = SqliteHistoryStore.open(
          path: p.join(dir.path, 'kusunga.db'),
          keyHex: _key,
        );
        final h = HistoryService(
          store: store,
          source: FakeClipboardSource(),
          log: log,
          snippetStore: store.snippetStore(),
          ignoredAppStore: store.ignoredAppStore(),
        )..start();
        addCloseTearDown(h);
        final r = await DataEraser(
          target: DefaultEraseTarget(keys: keys, folder: () async => dir),
          log: log,
          stopFileLog: () {},
        ).run(h);
        expect(r, isA<EraseFailed>());
        expect(log.details.single, 5);
        expect(keys.stored, _key);
      },
    );
  });

  group('R7a: when "can\'t be read any more" is true', () {
    late FakeLog log;
    late FakeKeyStore keys;
    setUp(() {
      log = FakeLog();
      keys = FakeKeyStore(stored: _key);
    });

    Future<EraseResult> run(
      List<String> stuck, {
      List<String> extra = const [],
      HistoryService? history,
      FakeKeyStore? keyStore,
    }) async {
      for (final n in [...stuck, ...extra]) {
        File(p.join(dir.path, n)).writeAsStringSync('x');
      }
      HistoryService h;
      if (history != null) {
        h = history;
      } else {
        final store = SqliteHistoryStore.open(
          path: p.join(dir.path, 'real', 'kusunga.db'),
          keyHex: _key,
        );
        h = HistoryService(
          store: store,
          source: FakeClipboardSource(),
          log: log,
          snippetStore: store.snippetStore(),
          ignoredAppStore: store.ignoredAppStore(),
        )..start();
        addCloseTearDown(h);
      }
      return DataEraser(
        target: DefaultEraseTarget(
          keys: keyStore ?? keys,
          folder: () async => dir,
        ),
        log: log,
        stopFileLog: () {},
        deleteEntity: (e) {
          if (stuck.contains(p.basename(e.path))) {
            throw const FileSystemException('busy', '', OSError('busy', 16));
          }
          e.deleteSync();
        },
      ).run(h);
    }

    test('only encrypted database files left, key gone: unreadable', () async {
      Directory(p.join(dir.path, 'real')).createSync();
      final r = await run([
        'kusunga.db',
        'kusunga.db-wal',
        'kusunga.db-journal',
        'kusunga.db.bak',
        'kusunga.db.unreadable-9',
      ]);
      expect(
        r,
        isA<Erased>().having((e) => e.leftUnreadable, 'unreadable', true),
      );
      expect((r as Erased).filesLeft, 5);
    });

    for (final other in ['kusunga.db-shm', 'kusunga.log', 'kusunga.log.1']) {
      test(
        '$other left with a database file: not claimed unreadable',
        () async {
          Directory(p.join(dir.path, 'real')).createSync();
          final r = await run(['kusunga.db', other]);
          expect(
            r,
            isA<Erased>().having((e) => e.leftUnreadable, 'unreadable', false),
          );
        },
      );
    }

    test('a link or a folder named like a database file that cannot be '
        'removed is not claimed unreadable', () async {
      Directory(p.join(dir.path, 'real')).createSync();
      Link(
        p.join(dir.path, 'kusunga.db.bak'),
      ).createSync(p.join(dir.path, 'nowhere'));
      final r = await run(['kusunga.db.bak']);
      expect(
        r,
        isA<Erased>().having((e) => e.leftUnreadable, 'unreadable', false),
      );
    }, skip: Platform.isWindows);

    test(
      'nothing left: filesLeft 0 and the plain "deleted" message applies',
      () async {
        Directory(p.join(dir.path, 'real')).createSync();
        final r = await run([]);
        expect(r, isA<Erased>().having((e) => e.filesLeft, 'left', 0));
      },
    );

    test('memory only: the key delete failed, so a leftover database file '
        'is not claimed unreadable', () async {
      keys.deleteError = StateError('no keychain');
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: log,
        notices: {HistoryNotice.memoryOnly},
      )..start();
      addCloseTearDown(h);
      final r = await run(['kusunga.db'], history: h);
      expect(
        r,
        isA<Erased>().having((e) => e.leftUnreadable, 'unreadable', false),
      );
    });

    test('a debug profile never claims it, even for a database file', () async {
      final profile = Directory(p.join(dir.path, 'profiles', 'qa'))
        ..createSync(recursive: true);
      File(p.join(profile.path, 'kusunga.db')).writeAsStringSync('x');
      final store = SqliteHistoryStore.open(
        path: p.join(dir.path, 'real.db'),
        keyHex: _key,
      );
      final h = HistoryService(
        store: store,
        source: FakeClipboardSource(),
        log: log,
        snippetStore: store.snippetStore(),
        ignoredAppStore: store.ignoredAppStore(),
      )..start();
      addCloseTearDown(h);
      final r = await DataEraser(
        target: ProfileEraseTarget(folder: () async => profile),
        log: log,
        stopFileLog: () {},
        deleteEntity: (e) => throw const FileSystemException('busy'),
      ).run(h);
      expect(
        r,
        isA<Erased>().having((e) => e.leftUnreadable, 'unreadable', false),
      );
    });
  });
}
