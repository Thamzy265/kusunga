// Tester probes for the own-marker rule (design note, abuse case 2) and for
// schema version 2: a forged marker must never skip a check or hide a copy,
// our own paste must never make a duplicate, and the v1 to v2 step must keep
// every item and leave the file alone if it fails.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

final _rlo = String.fromCharCode(0x202E);

void main() {
  late Directory dir;
  late FakeClipboardSource source;
  late FakeLog log;
  var clock = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_marker_');
    source = FakeClipboardSource();
    log = FakeLog();
    clock = 1000;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void own(String text) =>
      source.controller.add(ClipboardText(text, ownMarker: true));

  // The same rules must hold on the memory store and the encrypted file.
  final stores = <String, HistoryStore Function(Directory)>{
    'memory': (_) => MemoryHistoryStore(),
    'encrypted file': (d) =>
        SqliteHistoryStore.open(path: '${d.path}/k.db', keyHex: _key),
  };

  for (final entry in stores.entries) {
    group('own marker, ${entry.key} store', () {
      late HistoryStore store;
      late HistoryService service;

      setUp(() {
        store = entry.value(dir);
        service = HistoryService(
          store: store,
          source: source,
          log: log,
          clock: () => clock += 10,
        )..start();
      });
      tearDown(() {
        service.dispose();
        store.close();
      });

      List<String> texts() => [for (final i in service.items) i.preview];

      test('a forged marker on a near miss is saved as a new copy', () {
        source.copy('hello');
        // Differs by case, white space, a line ending, or Unicode form.
        for (final forged in [
          'Hello',
          'hello ',
          ' hello',
          'hello\n',
          'hello\r\n',
          'héllo',
          'hello\u200B',
        ]) {
          own(forged);
        }
        expect(store.count, 8, reason: 'every one is its own item');
        expect(texts().last, 'hello', reason: 'the real one was not bumped');
      });

      test('a collision attempt: same first 2,000 characters, same length, '
          'different end', () {
        final a = '${'x' * 3000}A';
        final b = '${'x' * 3000}B';
        source.copy(a);
        own(b);
        expect(store.count, 2);
        // a is older: it must not have been moved by the forged b
        expect(service.textOf(service.items.last.id), a);
        expect(service.textOf(service.items.first.id), b);
      });

      test('a forged marker on text that was only ever a prefix of a saved '
          'item does not move it', () {
        source.copy('the whole sentence');
        own('the whole');
        expect(store.count, 2);
        expect(texts().last, 'the whole sentence');
      });

      test('marker plus secret mark: nothing saved, nothing moved', () {
        source.copy('a');
        source.copy('b');
        source.controller.add(const ClipboardSkipped(SkipReason.concealed));
        expect(texts(), ['b', 'a']);
        expect(store.count, 2);
      });

      test('our own paste in a loop never creates a duplicate or evicts', () {
        for (final t in ['a', 'b', 'c']) {
          source.copy(t);
        }
        for (var i = 0; i < 12; i++) {
          own(['a', 'b', 'c'][i % 3]);
        }
        expect(store.count, 3);
        expect(texts(), ['c', 'b', 'a'], reason: 'order after 12 pastes');
        expect(log.codes, isEmpty);
      });

      test('pasting from a full history evicts nothing', () {
        service.setLimit(10);
        for (var i = 0; i < 10; i++) {
          source.copy('item $i');
        }
        own('item 0'); // the oldest
        expect(store.count, 10);
        expect(texts().first, 'item 0');
        expect(texts().last, 'item 1');
      });

      test('a 1 MiB item pasted by the picker is moved, not saved twice', () {
        final big = 'ab${'y' * (1024 * 1024 - 4)}yz';
        source.copy(big);
        source.copy('small');
        own(big);
        expect(store.count, 2);
        expect(service.textOf(service.items.first.id), big);
      });

      test('text with NUL, bidi and control characters moves to the top', () {
        final hostile = 'a\u0000b${_rlo}c\u200Bd\u0007e';
        source.copy(hostile);
        source.copy('other');
        own(hostile);
        expect(store.count, 2);
        expect(service.textOf(service.items.first.id), hostile);
      });

      test('a link pasted by the picker stays a link', () {
        source.copy('https://example.com/a');
        source.copy('plain');
        own('https://example.com/a');
        expect(service.items.first.kind, ClipKind.link);
        expect(store.count, 2);
      });

      test('the marker on an item of a different kind of text is just a '
          'copy: whitespace-only is still ignored', () {
        own('  ');
        expect(texts(), isEmpty);
      });
    });
  }

  group('own marker with a failing store', () {
    test('a saved item that cannot be moved is shown once, not twice', () {
      final flaky = FlakyStore(MemoryHistoryStore());
      final service = HistoryService(
        store: flaky,
        source: source,
        log: log,
        clock: () => clock += 10,
      )..start();
      addTearDown(service.dispose);
      source.copy('a');
      flaky.failWrites = true;
      own('a');
      expect([for (final i in service.items) i.preview], ['a']);
    });

    test('an unsaved (waiting) item pasted again stays one item', () {
      final flaky = FlakyStore(MemoryHistoryStore())..failWrites = true;
      final service = HistoryService(
        store: flaky,
        source: source,
        log: log,
        clock: () => clock += 10,
      )..start();
      addTearDown(service.dispose);
      source.copy('w');
      own('w');
      own('w');
      expect([for (final i in service.items) i.preview], ['w']);
    });
  });

  group('schema version 2', () {
    late FakeKeyStore keys;
    Future<OpenedHistory> open({List<Migration> migrations = kMigrations}) =>
        openHistory(
          keys: keys,
          directory: dir.path,
          log: log,
          random: Random(3),
          today: () => DateTime(2026, 11, 4),
          migrations: migrations,
        );

    setUp(() => keys = FakeKeyStore(stored: _key));

    void writeV1({int items = 25}) {
      final v1 = SqliteHistoryStore.open(
        path: '${dir.path}/kusunga.db',
        keyHex: _key,
        migrations: kMigrations.sublist(0, 1),
      );
      for (var i = 0; i < items; i++) {
        v1.insertOrBump('old $i', ClipKind.text, 100 + i);
      }
      v1.setLimit(30);
      v1.close();
    }

    test('a v1 file opens through the real opener, keeps everything, and '
        'takes the picker settings', () async {
      writeV1();
      final opened = await open();
      expect(opened.notices, isEmpty);
      expect(opened.store, isA<SqliteHistoryStore>());
      expect(opened.store.count, 25);
      expect(opened.store.limit, 30);
      opened.store.writeSetting('picker_shortcut', 'ctrl+alt+k');
      opened.store.writeSetting('paste_mode', 'copy_only');
      opened.store.close();
      final again = await open();
      expect(again.store.readSetting('picker_shortcut'), 'ctrl+alt+k');
      expect(again.store.readSetting('paste_mode'), 'copy_only');
      expect(again.store.count, 25);
      again.store.close();
      expect(File('${dir.path}/kusunga.db.bak').existsSync(), isFalse);
    });

    test('a failing v2 step: memory only, file and backup byte for byte '
        'untouched, no key written', () async {
      writeV1();
      final before = File('${dir.path}/kusunga.db').readAsBytesSync();
      final broken = [
        kMigrations[0],
        const Migration(version: 2, statements: ['THIS IS NOT SQL']),
      ];
      final opened = await open(migrations: broken);
      expect(opened.store, isA<MemoryHistoryStore>());
      expect(opened.notices, {HistoryNotice.incompatible});
      expect(File('${dir.path}/kusunga.db').readAsBytesSync(), before);
      expect(
        Directory(dir.path).listSync().map((e) => e.path.split('/').last),
        isNot(contains(startsWith('kusunga.db.unreadable'))),
        reason: 'the file must not be moved aside',
      );
      // Nothing this session does reaches the file.
      opened.store.insertOrBump('session only', ClipKind.text, 1);
      opened.store.writeSetting('picker_shortcut', 'ctrl+alt+k');
      opened.store.close();
      expect(File('${dir.path}/kusunga.db').readAsBytesSync(), before);
      expect(log.codes, contains(LogCode.storeIncompatible));
    });

    test(
      'a v1 build opening a v2 file leaves it untouched (rollback path)',
      () async {
        writeV1();
        (await open()).store.close();
        final before = File('${dir.path}/kusunga.db').readAsBytesSync();
        final old = await open(migrations: kMigrations.sublist(0, 1));
        expect(old.store, isA<MemoryHistoryStore>());
        expect(old.notices, {HistoryNotice.incompatible});
        old.store.close();
        expect(File('${dir.path}/kusunga.db').readAsBytesSync(), before);
      },
    );

    test('an empty v1 file migrates too', () async {
      writeV1(items: 0);
      final opened = await open();
      expect(opened.store.count, 0);
      expect(opened.notices, isEmpty);
      opened.store.close();
    });

    test('a damaged picker setting in the file reads back as the text it '
        'is, never throws', () async {
      final opened = await open();
      final store = opened.store;
      for (final bad in ['', ' ', '\u0000', 'x' * 64, '12', '1e5', '-0']) {
        if (bad.isEmpty) {
          expect(
            () => store.writeSetting('picker_shortcut', bad),
            throwsArgumentError,
          );
          continue;
        }
        store.writeSetting('picker_shortcut', bad);
        expect(store.readSetting('picker_shortcut'), isNotNull, reason: bad);
      }
      expect(() => store.readSetting('history_limit'), throwsArgumentError);
      expect(() => store.writeSetting('anything', 'x'), throwsArgumentError);
      store.close();
    });
  });
}
