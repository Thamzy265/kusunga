import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

/// WCAG 2.4.11 on the History tab (PM decision 2026-11-05, "Fix it here"):
/// Up/Down, Home/End and Cmd+Up/Down keep the focused row fully on screen,
/// at 100% and 200% text, in long lists of rows of one and two lines, and
/// after a delete and an Undo. The focus still moves at once when the row is
/// built (no frame is drawn for a key press alone).
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  setUp(() {
    source = FakeClipboardSource();
    final store = MemoryHistoryStore()..setLimit(5000);
    service = HistoryService(store: store, source: source, log: FakeLog())
      ..start();
  });
  tearDown(() => service.dispose());

  /// [n] copies, newest first in the list ("item n-1" at the top). Every
  /// third one has two lines, so rows differ in height.
  void fill(int n) {
    for (var i = 0; i < n; i++) {
      source.copy(i % 3 == 0 ? 'item $i\nsecond line' : 'item $i');
    }
  }

  Future<void> show(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: HistoryScreen(service: service),
      ),
    );
    await tester.pump();
  }

  ClipItem? focusedItem() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    ClipItem? item;
    if (ctx.widget is HistoryRow) return (ctx.widget as HistoryRow).item;
    ctx.visitAncestorElements((e) {
      if (e.widget is HistoryRow) {
        item = (e.widget as HistoryRow).item;
        return false;
      }
      return true;
    });
    return item;
  }

  /// The first line of the focused row's text.
  String? focusedText() => focusedItem()?.preview.split('\n').first;

  /// The focused row lies wholly inside the list's viewport.
  void expectFocusedOnScreen(WidgetTester tester, String reason) {
    final item = focusedItem();
    expect(item, isNotNull, reason: '$reason: a row has the focus');
    final row = tester.getRect(find.byKey(ValueKey('row-${item!.id}')));
    final view = tester.getRect(find.byType(CustomScrollView));
    expect(
      row.top >= view.top - 0.5 && row.bottom <= view.bottom + 0.5,
      isTrue,
      reason: '$reason: row $row is not inside $view',
    );
  }

  /// A key, then the frames it takes: a far row (End in 5,000) is reached
  /// in steps of at most 40 screens, one per frame.
  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> cmd(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  Future<void> focusTop(WidgetTester tester, int n) async {
    // On the text, not on a row button (at 200% text they wrap below it).
    final row = find.byKey(ValueKey('row-${service.items.first.id}'));
    await tester.tapAt(tester.getTopLeft(row) + const Offset(60, 16));
    await tester.pump();
    expect(focusedText(), 'item ${n - 1}');
  }

  for (final scale in [1.0, 2.0]) {
    final pct = '${(scale * 100).toInt()}%';

    testWidgets('$pct: Down 30 times, then Up 30 times, in 60 rows: every '
        'focused row is on screen', (tester) async {
      fill(60);
      await show(tester, textScale: scale);
      await focusTop(tester, 60);
      for (var i = 1; i <= 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump();
        expect(focusedText(), 'item ${59 - i}');
        expectFocusedOnScreen(tester, 'Down #$i');
      }
      for (var i = 1; i <= 30; i++) {
        await key(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedText(), 'item ${29 + i}');
        expectFocusedOnScreen(tester, 'Up #$i');
      }
    });

    for (final n in [400, 5000]) {
      testWidgets('$pct, $n rows: End, Home, Cmd+Down, Cmd+Up land on the '
          'right row, on screen, and Up/Down from there stay on screen', (
        tester,
      ) async {
        fill(n);
        await show(tester, textScale: scale);
        await focusTop(tester, n);
        await key(tester, LogicalKeyboardKey.end);
        expect(focusedText(), 'item 0');
        expectFocusedOnScreen(tester, 'End');
        for (var i = 1; i <= 12; i++) {
          await key(tester, LogicalKeyboardKey.arrowUp);
          expect(focusedText(), 'item $i');
          expectFocusedOnScreen(tester, 'Up #$i after End');
        }
        await key(tester, LogicalKeyboardKey.home);
        expect(focusedText(), 'item ${n - 1}');
        expectFocusedOnScreen(tester, 'Home');
        await cmd(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedText(), 'item 0');
        expectFocusedOnScreen(tester, 'Cmd+Down');
        await cmd(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedText(), 'item ${n - 1}');
        expectFocusedOnScreen(tester, 'Cmd+Up');
      });
    }
  }

  testWidgets('Down moves the focus at once when the next row is built', (
    tester,
  ) async {
    fill(60);
    await show(tester);
    await focusTop(tester, 60);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'item 58', reason: 'no pump needed');
  });

  testWidgets('End then Home with no frame between ends on the first row '
      '(a newer request cancels a stale one)', (tester) async {
    fill(400);
    await show(tester);
    await focusTop(tester, 400);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(focusedText(), 'item 399');
    expectFocusedOnScreen(tester, 'Home');
  });

  testWidgets('after a delete deep in the list, and after Undo, the focused '
      'row is on screen and Down keeps it there', (tester) async {
    fill(60);
    await show(tester);
    await focusTop(tester, 60);
    for (var i = 0; i < 25; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedText(), 'item 34');
    await key(tester, LogicalKeyboardKey.delete);
    await tester.pump();
    expect(focusedText(), 'item 33');
    expectFocusedOnScreen(tester, 'after Delete');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expectFocusedOnScreen(tester, 'Down after Delete');

    await tester.pump(const Duration(milliseconds: 400)); // toast slides in
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(service.items.map((i) => i.preview), contains('item 34'));
    await tester.tap(find.text('item 34'));
    await tester.pump();
    for (var i = 1; i <= 15; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectFocusedOnScreen(tester, 'Down #$i after Undo');
    }
    for (var i = 1; i <= 15; i++) {
      await key(tester, LogicalKeyboardKey.arrowUp);
      expectFocusedOnScreen(tester, 'Up #$i after Undo');
    }
  });
}
