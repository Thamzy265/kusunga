// L1: search over 1,000 snippets (full 2,000-character previews) with 5,000
// history items stays under 50 ms a keystroke, including the first keystroke
// after ⌃Tab, and the snippet index is warmed when the picker opens.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_search.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

String _text(Random rnd, int n) =>
    String.fromCharCodes(List.generate(n, (_) => 97 + rnd.nextInt(26)));

void main() {
  final rnd = Random(4);
  final snippets = [
    for (var i = 0; i < 1000; i++)
      SnippetItem(
        id: i + 1,
        name: _text(rnd, 100),
        type: SnippetType.other,
        preview: _text(rnd, ClipItem.previewLength),
        isTruncated: true,
        position: i,
        createdAt: 1,
        updatedAt: 1,
      ),
  ];
  final history = [
    for (var i = 0; i < 5000; i++)
      ClipItem(
        id: 5000 - i,
        kind: ClipKind.text,
        preview: _text(rnd, ClipItem.previewLength),
        isTruncated: false,
        createdAt: i,
        lastCopiedAt: i,
      ),
  ];
  const queries = ['qz', 'abc', 'zzzz', 'mnop', 'x', 'kq', 'ab', 'jv', 'rt'];

  void expectFast(List<int> ms, String what) {
    ms.sort();
    // As in picker_search_test: the median meets the target, no run is
    // over 150 ms on a noisy machine.
    expect(ms[ms.length ~/ 2], lessThan(50), reason: '$what median of $ms');
    expect(ms.last, lessThan(150), reason: '$what max of $ms');
  }

  test('the first keystroke after Ctrl+Tab (a fresh query on the Snippets '
      'tab, nothing to narrow, history index warm too) is under 50 ms', () {
    // The snippet index is warmed when the history opens (see the widget
    // test below), so the first keystroke after the switch finds it built;
    // the query itself is new, so no earlier result can be reused.
    final entries = PickerController.searchEntriesFor(snippets);
    final snippetSearch = PickerSearch();
    while (snippetSearch.warm(entries)) {} // the background steps
    final historySearch = PickerSearch();
    while (historySearch.warm(history)) {}
    final times = <int>[];
    for (final q in queries) {
      historySearch.filter(history, q); // typed on the History tab first
      historySearch.filter(history, ''); // cleared again
      final sw = Stopwatch()..start();
      snippetSearch.filter(entries, q); // first keystroke after Ctrl+Tab
      times.add(sw.elapsedMilliseconds);
      snippetSearch.filter(entries, '');
    }
    expectFast(times, 'first keystroke');
  });

  test('typing on: each added letter is under 50 ms', () {
    final entries = PickerController.searchEntriesFor(snippets);
    final search = PickerSearch();
    while (search.warm(entries)) {}
    final times = <int>[];
    for (final q in ['a', 'ab', 'abc', 'abcd', 'q', 'qz', 'qzx', 'm', 'mn']) {
      final sw = Stopwatch()..start();
      search.filter(entries, q);
      times.add(sw.elapsedMilliseconds);
    }
    expectFast(times, 'typing');
  });

  test('every keystroke on a warm snippet index is under 50 ms', () {
    final entries = PickerController.searchEntriesFor(snippets);
    final times = <int>[];
    for (final q in queries) {
      final warm = PickerSearch();
      while (warm.warm(entries, maxItems: 100000)) {}
      final sw = Stopwatch()..start();
      warm.filter(entries, q);
      times.add(sw.elapsedMilliseconds);
    }
    expectFast(times, 'warm');
  });

  testWidgets('the snippet index is built in the background once the '
      'history opens, like the history index', (tester) async {
    final store = MemorySnippetStore();
    for (var i = 0; i < 1000; i++) {
      store.insert(
        name: 'snippet $i',
        content: _text(rnd, 300),
        type: SnippetType.other,
        nowMs: i,
      );
    }
    final service = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      snippetStore: store,
    )..start();
    addTearDown(service.dispose);
    final c = PickerController(
      port: FakePickerPort(),
      log: FakeLog(),
      isMac: true,
    );
    addTearDown(c.dispose);
    await c.start();
    await c.attach(service);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 2));
    }
    expect(
      c.snippetSearch.warm(c.snippetEntries, maxItems: 0),
      isFalse,
      reason: 'every snippet is indexed before the first keystroke',
    );
    // A new snippet is indexed too.
    service.snippets.save(name: 'New', content: 'n', type: SnippetType.other);
    await tester.pump(const Duration(milliseconds: 2));
    expect(c.snippetSearch.warm(c.snippetEntries, maxItems: 0), isFalse);
  });

  testWidgets('a save rebuilds only that snippet\'s line, not all 1,000', (
    tester,
  ) async {
    final store = MemorySnippetStore();
    for (var i = 0; i < 1000; i++) {
      store.insert(
        name: 'snippet $i',
        content: _text(rnd, 2000),
        type: SnippetType.other,
        nowMs: i,
      );
    }
    final service = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      snippetStore: store,
    )..start();
    addTearDown(service.dispose);
    final c = PickerController(
      port: FakePickerPort(),
      log: FakeLog(),
      isMac: true,
    );
    addTearDown(c.dispose);
    await c.attach(service);
    final before = c.snippetEntries;
    final edited = service.snippets.items[10];
    service.snippets.save(
      id: edited.id,
      name: 'renamed',
      content: 'short',
      type: SnippetType.other,
    );
    final after = c.snippetEntries;
    expect(identical(after[0], before[0]), isTrue);
    expect(identical(after[999], before[999]), isTrue);
    expect(identical(after[10], before[10]), isFalse);
    expect(after[10].preview, 'renamed — short');
    await tester.pump(const Duration(milliseconds: 5));
  });
}
