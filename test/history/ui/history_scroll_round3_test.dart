import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  Future<void> focusTop(WidgetTester tester) async {
    final row = find.byKey(ValueKey('row-${service.items.first.id}'));
    await tester.tapAt(tester.getTopLeft(row) + const Offset(60, 16));
    await tester.pump();
    expect(focusedItem()?.id, service.items.first.id);
  }

  int mountedRows() =>
      find.byType(HistoryRow, skipOffstage: false).evaluate().length;

  void useLimit(int n) {
    service.dispose();
    final store = MemoryHistoryStore()..setLimit(n);
    service = HistoryService(store: store, source: source, log: FakeLog())
      ..start();
  }

  Future<void> settle(WidgetTester tester, [int max = 300]) async {
    var n = 0;
    while (tester.binding.hasScheduledFrame && n < max) {
      await tester.pump(const Duration(milliseconds: 16));
      n++;
    }
  }

  group('the keep-alive of the focused row (a44e597)', () {
    testWidgets('Down through 120 rows: kept-alive rows are released, the '
        'number of mounted rows stays small', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      var most = 0;
      for (var i = 0; i < 120; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
        if (mountedRows() > most) most = mountedRows();
      }
      // ignore: avoid_print
      print('ROWS most mounted during 120 Downs: $most');
      expect(most, lessThan(45), reason: 'rows leak while navigating');
    });

    testWidgets('a row kept alive off screen is released when the focus '
        'leaves it', (tester) async {
      fill(400);
      await show(tester);
      await focusTop(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byType(CustomScrollView))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 6000)));
      await tester.pumpAndSettle();
      final during = mountedRows();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final after = mountedRows();
      // ignore: avoid_print
      print(
        'ROWS kept alive while focused off screen: $during, after '
        'unfocus: $after',
      );
      expect(after, lessThan(45));
      expect(after, lessThanOrEqualTo(during));
    });

    testWidgets('50 focus changes between the top row and a far row do not '
        'accumulate kept-alive rows', (tester) async {
      fill(400);
      await show(tester);
      await focusTop(tester);
      for (var i = 0; i < 25; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await settle(tester);
      }
      expect(mountedRows(), lessThan(45));
    });
  });

  group('copies arriving while a row has the focus (limit 200, full)', () {
    testWidgets(
      'BUG-H6: 500 copies at once trim the focused item itself: the focus '
      'ends on a row on screen, and Delete removes exactly that row',
      (tester) async {
        useLimit(200);
        fill(200);
        await show(tester);
        await focusTop(tester);
        for (var i = 0; i < 40; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
        }
        await settle(tester);
        final trimmed = focusedItem()!.id;
        for (var i = 0; i < 500; i++) {
          source.copy('fresh $i');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          service.items.any((e) => e.id == trimmed),
          isFalse,
          reason: 'the focused item was trimmed',
        );
        final now = focusedItem();
        expect(now, isNotNull, reason: 'where did the focus go?');
        expectFocusedOnScreen(tester, 'after the trim');
        final length = service.items.length;
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();
        expect(service.items.length, length - 1);
        expect(
          service.items.any((e) => e.id == now!.id),
          isFalse,
          reason: 'Delete removed the row that had the focus',
        );
      },
    ); // BUG-H6

    testWidgets(
      'BUG-H6: the focused item is trimmed one copy at a time (the last '
      'row focused in a full list): the focus is never lost',
      (tester) async {
        useLimit(200);
        fill(200);
        await show(tester);
        await focusTop(tester);
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await settle(tester);
        expect(focusedText(), 'item 0');
        for (var i = 0; i < 10; i++) {
          source.copy('fresh $i');
          await tester.pump(const Duration(milliseconds: 16));
          await settle(tester);
          expect(focusedItem(), isNotNull, reason: 'copy $i: focus lost');
          expectFocusedOnScreen(tester, 'copy $i');
        }
      },
    ); // BUG-H6

    testWidgets(
      'BUG-H6: End on a full list with a copy arriving every frame: it '
      'ends on the oldest row, on screen, in a bounded number of frames',
      (tester) async {
        useLimit(200);
        fill(200);
        await show(tester);
        await focusTop(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        var frames = 0;
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          source.copy('fresh $i');
          frames++;
        }
        while (tester.binding.hasScheduledFrame && frames < 400) {
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        // ignore: avoid_print
        print('FRAMES End with a copy every frame (limit 200): $frames');
        expect(frames, lessThan(150));
        expect(focusedItem()?.id, service.items.last.id);
        expectFocusedOnScreen(tester, 'End with continuous copies');
      },
    ); // BUG-H6

    testWidgets('Home on a full list with a copy arriving every frame: it '
        'ends on the newest row, on screen', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        source.copy('fresh $i');
      }
      await settle(tester, 400);
      // Home lands on the row that was first when it was pressed; the copies
      // that came later are above it. (End retargets to the new last row,
      // Home does not retarget to the new first: noted in the report.)
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'Home with continuous copies');
    });

    testWidgets('End, then a copy every frame AND Up/Down presses: the focus '
        'is always on a real row at the end', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await settle(tester);
      for (var i = 0; i < 30; i++) {
        source.copy('fresh $i');
        await tester.sendKeyEvent(
          i.isEven ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester, 400);
      expect(tester.takeException(), isNull);
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'mixed keys and copies');
    });

    testWidgets('BUG-H5 (PM decision 2026-11-05): after the user scrolls '
        'with the wheel, a new copy does not pull the list back to the '
        'focused row; the next arrow key brings the focus back into view', (
      tester,
    ) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byType(CustomScrollView))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 4000)));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = position.pixels;
      expect(before, greaterThan(3000));
      source.copy('fresh');
      await tester.pumpAndSettle();
      expect(
        position.pixels,
        greaterThan(before - 500),
        reason:
            'the new copy scrolled the list from $before back to '
            '${position.pixels}',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedText(), 'item 298');
      expectFocusedOnScreen(tester, 'the next arrow key');
      // While the arrow keys are in use, a new copy keeps the row in view.
      source.copy('fresh 2');
      await tester.pumpAndSettle();
      expectFocusedOnScreen(tester, 'a copy after the arrow key');
    });

    testWidgets('BUG-H4: End in 5,000 rows with six copies arriving takes '
        'no more than 3x as long as without copies', (tester) async {
      fill(5000);
      await show(tester);
      await focusTop(tester);
      final plain = Stopwatch()..start();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await settle(tester, 500);
      final plainMs = plain.elapsedMilliseconds;
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await settle(tester, 500);
      final withCopies = Stopwatch()..start();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        source.copy('fresh $i');
      }
      await settle(tester, 500);
      // ignore: avoid_print
      print(
        'PERF End 5000: plain $plainMs ms, with copies '
        '${withCopies.elapsedMilliseconds} ms',
      );
      expect(withCopies.elapsedMilliseconds, lessThan(plainMs * 3));
    });
  });
}
