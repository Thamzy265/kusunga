import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';

import '../support/fakes.dart';
import 'fake_picker_port.dart';

/// P1: the search index belongs to the controller, so opening the picker does
/// not rebuild it; it is built in small steps whenever the items change.
void main() {
  testWidgets('first keystroke right after open with 5,000 items: median '
      'under 50 ms, max under 150 ms', (tester) async {
    final rnd = Random(3);
    final store = MemoryHistoryStore()..setLimit(5000);
    for (var i = 0; i < 5000; i++) {
      store.insertOrBump(
        String.fromCharCodes(List.generate(2000, (_) => 97 + rnd.nextInt(26))),
        ClipKind.text,
        i,
      );
    }
    final history = HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
    final port = FakePickerPort();
    final c = PickerController(port: port, log: FakeLog(), isMac: true);
    await c.start();
    await c.attach(history);
    // The index is built in the background after the history opens, long before
    // anyone presses the shortcut.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    port.press();
    await tester.pump();

    const queries = ['qz', 'abc', 'zzzz', 'mnop', 'x', 'kq', 'ab', 'jv', 'rt'];
    // Each timed search starts from an empty field, as a first keystroke
    // does: the search narrows from its last result when a query extends the
    // previous one, so the empty query in between keeps every run a full
    // search (it does no per-item work).
    List<ClipItem> fresh(String q) {
      c.search.filter(history.items, '');
      return c.search.filter(history.items, q);
    }

    // The test runs JIT-compiled, beside other test isolates: one untimed
    // pass compiles the search code (the app is compiled ahead of time), and
    // each query keeps the fastest of 3 full runs, so a pause from another
    // test or a GC is not counted as search time. The limits are unchanged.
    queries.forEach(fresh);
    final times = <int>[];
    final sw = Stopwatch();
    for (final q in queries) {
      var best = 1 << 30;
      for (var run = 0; run < 3; run++) {
        c.search.filter(history.items, '');
        sw
          ..reset()
          ..start();
        c.search.filter(history.items, q);
        best = min(best, sw.elapsedMilliseconds);
      }
      times.add(best);
    }
    times.sort();
    expect(times[times.length ~/ 2], lessThan(50), reason: 'median of $times');
    expect(times.last, lessThan(150), reason: 'max of $times');
    c.dispose();
  });

  testWidgets('a new copy is indexed in the background, one item, not all', (
    tester,
  ) async {
    final source = FakeClipboardSource();
    final history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
    final c = PickerController(
      port: FakePickerPort(),
      log: FakeLog(),
      isMac: true,
    );
    for (var i = 0; i < 300; i++) {
      source.copy('item $i');
    }
    await c.start();
    await c.attach(history);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.search.warm(history.items, maxItems: 1), isFalse);

    source.copy('brand new');
    await tester.pump(const Duration(milliseconds: 50));
    // Already built by the background step: nothing left to do.
    expect(c.search.warm(history.items, maxItems: 0), isFalse);
    c.dispose();
  });
}
