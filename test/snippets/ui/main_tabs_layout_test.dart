// QA-M14-1: at 600 px and wider the tabs and New snippet share one row, and
// each tab is only as wide as its label (UI spec, Layout and Breakpoints).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  Future<void> show(WidgetTester tester, Size size, {double scale = 1}) async {
    final service = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: HistoryHost(history: Future.value(service)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('main-tab-snippets'));
    await tester.pump();
  }

  Rect tab(WidgetTester tester, String name) =>
      tester.getRect(find.bySemanticsIdentifier('main-tab-$name'));
  Rect label(WidgetTester tester, String text) => tester.getRect(
    find.descendant(
      of: find.bySemanticsIdentifier('main-tab-${text.toLowerCase()}'),
      matching: find.text(text),
    ),
  );
  Rect newButton(WidgetTester tester) =>
      tester.getRect(find.bySemanticsIdentifier('snippet-new'));

  testWidgets('800 px: History, Snippets and New snippet on one row; each '
      'tab only as wide as its label', (tester) async {
    await show(tester, const Size(800, 632));
    final h = tab(tester, 'history');
    final s = tab(tester, 'snippets');
    final n = newButton(tester);
    expect(h.center.dy, moreOrLessEquals(s.center.dy, epsilon: 1));
    expect(n.center.dy, moreOrLessEquals(h.center.dy, epsilon: 12));
    expect(h.right, lessThanOrEqualTo(s.left + 0.5), reason: 'side by side');
    expect(s.right, lessThan(n.left), reason: 'New is to the right');
    expect(n.right, greaterThan(700), reason: 'New sits at the right');
    for (final name in ['History', 'Snippets']) {
      final t = tab(tester, name.toLowerCase());
      final l = label(tester, name);
      // The label plus its padding and focus ring: never the whole row.
      expect(t.width, lessThan(l.width + 48), reason: '$name is $t');
      expect(t.width, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('600 px: still one row', (tester) async {
    await show(tester, const Size(600, 632));
    final h = tab(tester, 'history');
    expect(
      tab(tester, 'snippets').center.dy,
      moreOrLessEquals(h.center.dy, epsilon: 1),
    );
    expect(
      newButton(tester).center.dy,
      moreOrLessEquals(h.center.dy, epsilon: 12),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('under 600 px the tabs and New may wrap to two rows, tabs stay '
      'together, nothing overflows', (tester) async {
    await show(tester, const Size(360, 632));
    final h = tab(tester, 'history');
    final s = tab(tester, 'snippets');
    expect(s.center.dy, moreOrLessEquals(h.center.dy, epsilon: 1));
    expect(h.width, lessThan(label(tester, 'History').width + 48));
    expect(newButton(tester).right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('360 px at 200% text: wraps, no overflow, no sideways scroll', (
    tester,
  ) async {
    await show(tester, const Size(360, 400), scale: 2);
    for (final r in [
      tab(tester, 'history'),
      tab(tester, 'snippets'),
      newButton(tester),
    ]) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    }
    expect(tester.takeException(), isNull);
  });
}
