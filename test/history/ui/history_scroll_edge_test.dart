import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

/// Tester round 2 on 51c474b (History keeps the focused row on screen): rows
/// of one, two and four lines, a delete while a stepping scroll is running,
/// copies arriving while navigating, a resize, End then Down, an empty list,
/// and how many frames End takes in 5,000 rows. (The History tab has no
/// search field, so a filter cannot be tested.)
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

  /// Rows of 1, 2 and 4 lines, in a fixed irregular pattern.
  void fill(int n) {
    for (var i = 0; i < n; i++) {
      final lines = switch (i % 7) {
        0 || 3 => 2,
        5 => 4,
        _ => 1,
      };
      source.copy(
        ['item $i', for (var l = 1; l < lines; l++) 'line $l'].join('\n'),
      );
    }
  }

  Future<void> show(
    WidgetTester tester, {
    double textScale = 1,
    Size size = const Size(800, 632),
  }) async {
    tester.view.physicalSize = size;
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

  String? focusedText() => focusedItem()?.preview.split('\n').first;

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

  /// Frames drawn after [k] until nothing asks for another (at most 500).
  Future<int> framesAfter(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    var n = 0;
    while (tester.binding.hasScheduledFrame && n < 500) {
      await tester.pump(const Duration(milliseconds: 16));
      n++;
    }
    return n;
  }

  Future<void> focusTop(WidgetTester tester) async {
    final row = find.byKey(ValueKey('row-${service.items.first.id}'));
    await tester.tapAt(tester.getTopLeft(row) + const Offset(60, 16));
    await tester.pump();
    expect(focusedItem()?.id, service.items.first.id);
  }

  testWidgets('End in 5,000 rows of mixed height finishes in a bounded '
      'number of frames, on the last row, on screen', (tester) async {
    fill(5000);
    await show(tester);
    await focusTop(tester);
    final frames = await framesAfter(tester, LogicalKeyboardKey.end);
    // ignore: avoid_print
    print('FRAMES End in 5000 rows: $frames');
    expect(frames, lessThan(100), reason: 'End took $frames frames');
    expect(focusedText(), 'item 0');
    expectFocusedOnScreen(tester, 'End');
    final back = await framesAfter(tester, LogicalKeyboardKey.home);
    // ignore: avoid_print
    print('FRAMES Home in 5000 rows: $back');
    expect(back, lessThan(100));
    expect(focusedText(), 'item 4999');
    expectFocusedOnScreen(tester, 'Home');
  });

  testWidgets('End, then Down: the last row keeps the focus and stays on '
      'screen; then Up goes to the one above it', (tester) async {
    fill(300);
    await show(tester);
    await focusTop(tester);
    await framesAfter(tester, LogicalKeyboardKey.end);
    await framesAfter(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'item 0');
    expectFocusedOnScreen(tester, 'Down at the end');
    await framesAfter(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedText(), 'item 1');
    expectFocusedOnScreen(tester, 'Up from the end');
  });

  testWidgets('Home on the first row and Up on the first row stay put', (
    tester,
  ) async {
    fill(40);
    await show(tester);
    await focusTop(tester);
    await framesAfter(tester, LogicalKeyboardKey.home);
    await framesAfter(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedText(), 'item 39');
    expectFocusedOnScreen(tester, 'Home at the top');
  });

  testWidgets('an empty list: Home, End, Up, Down, Cmd+Up, Cmd+Down do '
      'nothing and throw nothing', (tester) async {
    await show(tester);
    for (final k in [
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await framesAfter(tester, k);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focusedItem(), isNull);
  });

  testWidgets('a list that becomes empty while End is stepping does not '
      'loop or throw', (tester) async {
    fill(3000);
    await show(tester);
    await focusTop(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    service.clear();
    var n = 0;
    while (tester.binding.hasScheduledFrame && n < 500) {
      await tester.pump(const Duration(milliseconds: 16));
      n++;
    }
    expect(n, lessThan(300), reason: 'the stepping scroll gave up');
    expect(tester.takeException(), isNull);
  });

  group('mixed 1-, 2- and 4-line rows', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${(scale * 100).toInt()}%: Down 60, End, Up 25, Home, '
          'every focused row on screen', (tester) async {
        fill(1500);
        await show(tester, textScale: scale);
        await focusTop(tester);
        for (var i = 1; i <= 60; i++) {
          await framesAfter(tester, LogicalKeyboardKey.arrowDown);
          expect(focusedText(), 'item ${1499 - i}');
          expectFocusedOnScreen(tester, 'Down #$i');
        }
        await framesAfter(tester, LogicalKeyboardKey.end);
        expect(focusedText(), 'item 0');
        expectFocusedOnScreen(tester, 'End');
        for (var i = 1; i <= 25; i++) {
          await framesAfter(tester, LogicalKeyboardKey.arrowUp);
          expect(focusedText(), 'item $i');
          expectFocusedOnScreen(tester, 'Up #$i');
        }
        await framesAfter(tester, LogicalKeyboardKey.home);
        expect(focusedText(), 'item 1499');
        expectFocusedOnScreen(tester, 'Home');
      });
    }
  });

  group('while a stepping scroll is in progress', () {
    testWidgets('a delete of another row (from the row buttons of a toast, '
        'a trim) while End steps: End still lands on the last row, on '
        'screen', (tester) async {
      fill(5000);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump(const Duration(milliseconds: 16));
      service.delete(service.items[2500].id);
      service.delete(service.items[10].id);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.items.length, 4998);
      expect(focusedText(), 'item 0');
      expectFocusedOnScreen(tester, 'End across deletes');
    });

    testWidgets('BUG-H1: the End target (the oldest item) is deleted by '
        'something else mid-way (a full history trims its oldest copy when a '
        'new one arrives): the focus ends on a row, on screen', (tester) async {
      fill(5000);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      service.delete(service.items.last.id);
      var n = 0;
      while (tester.binding.hasScheduledFrame && n < 500) {
        await tester.pump(const Duration(milliseconds: 16));
        n++;
      }
      expect(n, lessThan(300));
      expect(tester.takeException(), isNull);
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'after the target vanished');
    }); // BUG-H1

    testWidgets('copies arriving at the top while End steps: End still '
        'ends on the oldest row, on screen', (tester) async {
      fill(3000);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        source.copy('fresh $i');
      }
      await tester.pumpAndSettle();
      expect(focusedText(), 'item 0');
      expectFocusedOnScreen(tester, 'End with new copies');
    });

    testWidgets('a resize while End steps: the row is on screen in the '
        'new, smaller window', (tester) async {
      fill(3000);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      tester.view.physicalSize = const Size(420, 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(focusedText(), 'item 0');
      expectFocusedOnScreen(tester, 'End across a resize');
    });
  });

  group('while navigating with Down and Up', () {
    testWidgets('BUG-H3: new copies arriving at the top do not move the '
        'focus to another row (a Delete would hit the wrong item)', (
      tester,
    ) async {
      fill(200);
      await show(tester);
      await focusTop(tester);
      for (var i = 0; i < 20; i++) {
        await framesAfter(tester, LogicalKeyboardKey.arrowDown);
      }
      final focusedBefore = focusedItem()!.id;
      for (var i = 0; i < 5; i++) {
        source.copy('fresh $i');
        await tester.pump();
      }
      expect(focusedItem()!.id, focusedBefore, reason: 'the focus stays');
      await framesAfter(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedText(), 'item ${199 - 21}');
      expectFocusedOnScreen(tester, 'Down after new copies');
      await framesAfter(tester, LogicalKeyboardKey.arrowUp);
      await framesAfter(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'item ${199 - 20 + 1}');
      expectFocusedOnScreen(tester, 'Up after new copies');
    }); // BUG-H3

    testWidgets('the focused row copied again (it moves to the top): the '
        'focus follows it and Down goes on from the top', (tester) async {
      fill(100);
      await show(tester);
      await focusTop(tester);
      for (var i = 0; i < 12; i++) {
        await framesAfter(tester, LogicalKeyboardKey.arrowDown);
      }
      final text = focusedItem()!.preview;
      source.copy(text);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await framesAfter(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'Down after the row moved to the top');
    });

    testWidgets('BUG-H2: Down in a short window must not throw (the stepping '
        'estimate reads the render object of a disposed row)', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      for (var i = 0; i < 5; i++) {
        await framesAfter(tester, LogicalKeyboardKey.arrowDown);
      }
      tester.view.physicalSize = const Size(380, 260);
      await tester.pumpAndSettle();
      for (var i = 0; i < 15; i++) {
        await framesAfter(tester, LogicalKeyboardKey.arrowDown);
        expect(tester.takeException(), isNull, reason: 'Down #$i');
        expectFocusedOnScreen(tester, 'Down #$i in the short window');
      }
      await framesAfter(tester, LogicalKeyboardKey.end);
      expect(focusedText(), 'item 0');
      expectFocusedOnScreen(tester, 'End in the short window');
    }); // BUG-H2

    testWidgets('Down 40 times in a window that is short from the start '
        '(380x260) keeps each row on screen, without exceptions', (
      tester,
    ) async {
      fill(300);
      await show(tester, size: const Size(380, 260));
      await focusTop(tester);
      for (var i = 1; i <= 40; i++) {
        await framesAfter(tester, LogicalKeyboardKey.arrowDown);
        expect(tester.takeException(), isNull, reason: 'Down #$i');
        expectFocusedOnScreen(tester, 'Down #$i');
      }
    });
  });
}
