// M1.7 tester, second pass: an id kept from before an item expired gives
// nothing (R1), to the millisecond, for copy, paste from the picker, and the
// text "Save as snippet" opens with. Memory and real SQLite stores.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

const day = Duration.millisecondsPerDay;
const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late HistoryStore store;
  late Directory dir;
  var now = 0;
  var written = <String>[];

  setUp(() {
    now = 200 * day;
    written = [];
    dir = Directory.systemTemp.createTempSync('kusunga_stale_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryService build(int days) {
    store.writeSetting(historyExpirySetting, '$days');
    return HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: FakeLog(),
      clock: () => now,
      writeClipboard: (t) async => written.add(t),
    )..start();
  }

  for (final kind in ['memory', 'sqlite']) {
    group('$kind store', () {
      setUp(() {
        store = kind == 'memory'
            ? MemoryHistoryStore()
            : SqliteHistoryStore.open(path: '${dir.path}/k.db', keyHex: _key);
      });
      tearDown(() => store.close());

      test('contentOf with notBefore: kept at exactly the cutoff, gone 1 ms '
          'older, unfiltered without it', () {
        final edge = store.insertOrBump('x', ClipKind.text, 1000);
        expect(store.contentOf(edge, notBefore: 1000), 'x');
        expect(store.contentOf(edge, notBefore: 1001), isNull);
        expect(store.contentOf(edge), 'x');
        expect(store.contentOf(edge, notBefore: -0x8000000000000000), 'x');
        expect(store.contentOf(9999, notBefore: 0), isNull);
      });

      for (final days in [1, 7, 30]) {
        test('$days day(s): textOf and copy at exactly that age work; 1 ms '
            'later they give nothing', () async {
          // Seed after start so the launch clean-up does not remove it.
          final service = build(days);
          addTearDown(service.dispose);
          final id = store.insertOrBump('keep me', ClipKind.text, now);
          now += days * day; // exactly N days old
          expect(service.textOf(id), 'keep me');
          expect(await service.copy(id), isTrue);
          expect(written, ['keep me']);
          now += 1;
          expect(service.textOf(id), isNull);
          expect(await service.copy(id), isFalse);
          expect(written, ['keep me'], reason: 'nothing more was copied');
        });
      }

      test('Never: an old id still works', () async {
        final service = build(0);
        addTearDown(service.dispose);
        final id = store.insertOrBump('old', ClipKind.text, 1);
        expect(service.textOf(id), 'old');
      });

      test('a re-copy revives the id (last copy is new)', () async {
        final service = build(1);
        addTearDown(service.dispose);
        final id = store.insertOrBump('again', ClipKind.text, now);
        now += 2 * day;
        expect(service.textOf(id), isNull);
        store.insertOrBump('again', ClipKind.text, now);
        expect(service.textOf(id), 'again');
      });

      test('picker: pasting a stale id does not paste, and logs no paste '
          'source', () async {
        final service = build(1);
        addTearDown(service.dispose);
        final id = store.insertOrBump('stale', ClipKind.text, now);
        now += day + 1;
        final port = FakePickerPort();
        final log = FakeLog();
        final c = PickerController(port: port, log: log, isMac: true);
        addTearDown(c.dispose);
        await c.start();
        await c.attach(service);
        port.press();
        port.calls.clear();
        log.codes.clear();
        await c.pasteItem(id);
        expect(port.calls, isNot(contains('paste')));
        expect(log.codes, isEmpty);
      });
    });
  }
}
