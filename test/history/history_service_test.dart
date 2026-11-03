import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late FlakyStore store;
  late FakeLog log;
  late HistoryService service;
  late List<String> written;
  var now = 0;

  HistoryService build({
    Set<HistoryNotice> notices = const {},
    ErrorLog? errorLog,
  }) => HistoryService(
    store: store,
    notices: notices,
    source: source,
    log: errorLog ?? log,
    clock: () => now += 10,
    writeClipboard: (text) async => written.add(text),
  )..start();

  setUp(() {
    now = 1000;
    source = FakeClipboardSource();
    store = FlakyStore(MemoryHistoryStore());
    log = FakeLog();
    written = [];
    service = build();
  });
  tearDown(() => service.dispose());

  List<String> texts() => service.items.map((i) => i.preview).toList();

  test('a copied text appears at once, as text or link', () {
    var notified = 0;
    service.addListener(() => notified++);

    source.copy('hello');
    source.copy('https://example.com');

    expect(texts(), ['https://example.com', 'hello']);
    expect(service.items.first.kind, ClipKind.link);
    expect(service.items.last.kind, ClipKind.text);
    expect(notified, greaterThanOrEqualTo(2));
  });

  test('a duplicate moves to the top', () {
    source.copy('a');
    source.copy('b');
    source.copy('a');
    expect(texts(), ['a', 'b']);
  });

  test('secret-marked copies are never saved', () {
    source.controller.add(const ClipboardSkipped(SkipReason.concealed));
    expect(service.items, isEmpty);
    expect(store.count, 0);
  });

  test('copies over 1 MB are skipped, counted in the log, never stored', () {
    source.controller.add(const ClipboardSkipped(SkipReason.tooLarge));
    source.copy('x' * (ClipItem.maxContentLength + 1));
    expect(store.count, 0);
    expect(log.codes, [LogCode.clipboardTooLarge, LogCode.clipboardTooLarge]);
  });

  test('empty and whitespace-only copies are ignored', () {
    source.copy('');
    source.copy('  \n\t ');
    expect(service.items, isEmpty);
  });

  test('text is saved exactly as copied, not trimmed', () {
    source.copy('  padded\n');
    expect(store.contentOf(service.items.single.id), '  padded\n');
  });

  test('a failing watcher is logged and does not crash the app', () {
    source.controller.addError(Exception('watcher gone'));
    expect(log.codes, [LogCode.clipboardChannelError]);
    source.copy('still works');
    expect(texts(), ['still works']);
  });

  test('a read error is logged with its code only', () {
    source.controller.add(const ClipboardReadError('locked'));
    expect(log.codes, [LogCode.clipboardLocked]);
    expect(service.items, isEmpty);
  });

  group('write failures', () {
    test('the item stays in memory, a banner shows, nothing crashes', () {
      store.failWrites = true;
      source.copy('kept in memory');

      expect(texts(), ['kept in memory']);
      expect(service.banners, {HistoryBanner.writeError});
      expect(store.count, 0);
      expect(log.codes, [LogCode.writeFailed]);
    });

    test('the next copy retries the waiting items first', () {
      store.failWrites = true;
      source.copy('first');
      store.failWrites = false;
      source.copy('second');

      expect(store.inner.list().map((i) => i.preview), ['second', 'first']);
      expect(service.banners, isEmpty);
      expect(texts(), ['second', 'first']);
    });

    test('if the retry fails too, everything waits and the banner stays', () {
      store.failWrites = true;
      source.copy('first');
      source.copy('second');
      expect(texts(), ['second', 'first']);
      expect(service.banners, {HistoryBanner.writeError});
    });

    test('a waiting item can be deleted and does not come back', () {
      store.failWrites = true;
      source.copy('first');
      final id = service.items.single.id;
      expect(service.delete(id)?.content, 'first');
      store.failWrites = false;
      source.copy('second');
      expect(texts(), ['second']);
    });
  });

  test('Copy puts the whole text on the clipboard', () async {
    source.copy('x' * 5000);
    final ok = await service.copy(service.items.single.id);
    expect(ok, isTrue);
    expect(written.single.length, 5000);
  });

  test('Copy reports failure instead of throwing', () async {
    source.copy('a');
    final failing = HistoryService(
      store: store,
      source: source,
      log: log,
      writeClipboard: (_) async => throw Exception('no'),
    );
    expect(await failing.copy(service.items.single.id), isFalse);
    failing.dispose();
  });

  test('delete returns the item; undo restores it in place', () {
    source.copy('a');
    source.copy('b');
    source.copy('c');
    final removed = service.delete(service.items[1].id)!;
    expect(texts(), ['c', 'a']);
    service.undo(removed);
    expect(texts(), ['c', 'b', 'a']);
  });

  test('clear removes all items; a failure shows the clear banner', () {
    source.copy('a');
    source.copy('b');
    store.failClear = true;
    expect(service.clear(), isNull);
    expect(service.banners, {HistoryBanner.clearError});
    expect(texts(), ['b', 'a']);

    store.failClear = false;
    expect(service.clear(), 2);
    expect(service.items, isEmpty);
    expect(service.banners, isEmpty, reason: 'a good clear removes the error');
  });

  test('the limit: valid values save, others are refused', () {
    expect(service.limit, 200);
    expect(service.setLimit(50), isTrue);
    expect(service.limit, 50);
    expect(service.setLimit(9), isFalse);
    expect(service.setLimit(5001), isFalse);
    expect(service.limit, 50);
  });

  test('lowering the limit trims and refreshes the list', () {
    for (var i = 0; i < 15; i++) {
      source.copy('item $i');
    }
    expect(service.countRemovedBy(10), 5);
    service.setLimit(10);
    expect(service.items.length, 10);
  });

  group('banners', () {
    test('open-time notices become banners and can be dismissed', () {
      final s = build(
        notices: {HistoryNotice.memoryOnly, HistoryNotice.readError},
      );
      expect(s.banners, {HistoryBanner.memoryOnly, HistoryBanner.readError});
      s.dismiss(HistoryBanner.readError);
      expect(s.banners, {HistoryBanner.memoryOnly});
      s.dispose();
    });
  });

  group('Mac paste access', () {
    test('is asked at start and can be re-checked', () async {
      source.access = PasteAccess.needsSetup;
      final s = build();
      await pumpEventQueue();
      expect(s.pasteAccess, PasteAccess.needsSetup);

      source.access = PasteAccess.allowed;
      await s.recheckPasteAccess();
      expect(s.pasteAccess, PasteAccess.allowed);
      s.dispose();
    });
  });

  group('closing', () {
    test('close flushes the store once and ignores later copies', () async {
      source.copy('before');
      await service.close();
      await service.close();
      source.copy('after');
      expect(store.closes, 1);
      expect(service.items, isEmpty);
    });
  });

  test('clipboard text never reaches the log file', () {
    final dir = Directory.systemTemp.createTempSync('kusunga_svc_log_');
    final file = File('${dir.path}/kusunga.log');
    final s = build(errorLog: FileErrorLog(file));
    const marker = 'UNIQUE-MARKER-7c1e-9a04-not-a-secret';
    store.failWrites = true;
    source.copy(marker);
    source.controller.add(const ClipboardReadError('locked'));
    source.copy('x' * (ClipItem.maxContentLength + 1));

    expect(file.readAsStringSync(), isNot(contains(marker)));
    expect(file.readAsStringSync(), contains('writeFailed'));
    s.dispose();
    dir.deleteSync(recursive: true);
  });
}
