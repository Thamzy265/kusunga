// Windows CI green (group A), tester: the helper against a real encrypted
// database file. macOS lets a test delete a file that is still open, so a
// test that forgets the helper passes on a Mac and fails only on Windows
// (errno 32). This file shows on a Mac, with lsof, what Windows would trip
// over: whether the database file is still open when the folder goes.
//
// What cannot be caught on a Mac: a test file that forgets the helper. The
// only run that fails for it is Windows CI.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:path/path.dart' as p;

import 'close_service.dart';
import 'fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// Whether this process still holds [path] open (macOS and Linux).
bool _heldOpen(String path) {
  final r = Process.runSync('lsof', ['-p', '$pid', '-Fn']);
  return (r.stdout as String).split('\n').any((l) => l == 'n$path');
}

void main() {
  final noLsof = Platform.isWindows ? 'lsof needs a POSIX system' : false;
  late Directory dir;
  late String db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_close_');
    // The real path, as lsof prints it (/var is a link to /private/var).
    db = p.join(dir.resolveSymbolicLinksSync(), 'kusunga.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryService open() {
    final store = SqliteHistoryStore.open(path: db, keyHex: _key);
    return HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: FakeLog(),
    )..start();
  }

  test('lsof sees the database open while the service lives', () {
    final h = open();
    expect(File(db).existsSync(), isTrue);
    expect(_heldOpen(db), isTrue, reason: 'the probe itself must work');
    return closeAndDispose(h);
  }, skip: noLsof);

  test(
    'dispose() alone leaves the database file open: the Windows failure',
    () async {
      final h = open()..dispose();
      expect(_heldOpen(db), isTrue);
      await h.close(); // let go, so the tear-down can finish
    },
    skip: noLsof,
  );

  test('closeAndDispose lets go of the database file', () async {
    await closeAndDispose(open());
    expect(_heldOpen(db), isFalse);
  }, skip: noLsof);

  group('tear-down order: the helper runs before the folder is deleted', () {
    final seen = <String>[];
    late HistoryService h;

    // Registered before the test body, so it runs after the test's own
    // tear-downs: the same place as the folder deletion in the test files.
    tearDown(() {
      seen.add(_heldOpen(db) ? 'open at folder deletion' : 'closed');
    });

    test('addCloseTearDown', () {
      seen.clear();
      h = open();
      addCloseTearDown(h);
      expect(_heldOpen(db), isTrue);
    }, skip: noLsof);

    test('(checked after the one above)', () {
      expect(seen, ['closed']);
      expect(
        () => h.addListener(() {}),
        throwsFlutterError,
        reason: 'it was disposed too',
      );
    }, skip: noLsof);
  });

  test('closeAndDispose twice, and after close(), does not throw', () async {
    final h = open();
    await h.close();
    await closeAndDispose(h);
    await closeAndDispose(h);
    expect(_heldOpen(db), isFalse);
  }, skip: noLsof);
}
