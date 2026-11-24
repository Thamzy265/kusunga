import 'package:flutter/gestures.dart';
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

/// Tester round 4 on 6961ab2 (no keep-alive: the focus follows the item by
/// id and waits on the screen node when its row is disposed; a trimmed
/// focused item moves the focus to the nearest remaining item; the focused
/// row is kept in view only while the arrow keys are in use).
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

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  /// A mouse wheel scroll of [dy] pixels over the list.
  Future<void> wheel(WidgetTester tester, double dy) async {
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byType(CustomScrollView))),
    );
    await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await settle(tester);
  }

  group('focus waits on the screen node (its row scrolled away by the '
      'mouse): no key but the arrows does anything', () {
    for (final (label, k) in [
      ('Delete', LogicalKeyboardKey.delete),
      ('Backspace', LogicalKeyboardKey.backspace),
      ('Enter', LogicalKeyboardKey.enter),
      ('S (Save as snippet)', LogicalKeyboardKey.keyS),
      ('Space', LogicalKeyboardKey.space),
      ('E', LogicalKeyboardKey.keyE),
      ('F2', LogicalKeyboardKey.f2),
    ]) {
      testWidgets('$label does nothing: no delete, no copy, no editor', (
        tester,
      ) async {
        fill(300);
        await show(tester);
        await focusTop(tester);
        final focused = focusedItem()!.id;
        await wheel(tester, 4000);
        expect(
          focusedItem(),
          isNull,
          reason: 'the row was scrolled away, so no row has the focus',
        );
        final before = [for (final i in service.items) i.id];
        await key(tester, k);
        expect(
          [for (final i in service.items) i.id],
          before,
          reason: '$label changed the history',
        );
        expect(service.snippets.items, isEmpty);
        expect(find.byType(Dialog), findsNothing);
        expect(service.items.any((i) => i.id == focused), isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Delete in the same frame as the arrow key that brings the '
        'focus back hits at most the followed item', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await wheel(tester, 4000);
      final before = service.items.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);
      expect(service.items.length, greaterThanOrEqualTo(before - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the arrow keys, Home and End carry on from the item that '
        'lost the focus, and bring it into view', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await wheel(tester, 4000);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedText(), 'item 298');
      expectFocusedOnScreen(tester, 'Down after the wheel');
      await wheel(tester, 3000);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'item 299');
      expectFocusedOnScreen(tester, 'Up after the wheel');
      await wheel(tester, 3000);
      await key(tester, LogicalKeyboardKey.end);
      expect(focusedText(), 'item 0');
      expectFocusedOnScreen(tester, 'End after the wheel');
      await wheel(tester, -9000);
      await key(tester, LogicalKeyboardKey.home);
      expect(focusedText(), 'item 299');
      expectFocusedOnScreen(tester, 'Home after the wheel');
    });

    testWidgets('while the focus waits, the followed item is deleted by '
        'something else: the next arrow key still lands on a row', (
      tester,
    ) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await wheel(tester, 4000);
      service.delete(service.items.first.id);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'after the followed item was deleted');
      expect(tester.takeException(), isNull);
    });
  });

  group('a trim of the focused item (limit 200, full)', () {
    testWidgets('a copy and a Delete key in the same frame: the Delete does '
        'not remove a second item', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester);
      await focusTop(tester);
      await key(tester, LogicalKeyboardKey.end);
      expect(focusedText(), 'item 0');
      source.copy('fresh'); // trims item 0, the focused one
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // same frame
      await settle(tester);
      expect(
        service.items.length,
        inInclusiveRange(199, 200),
        reason: 'one Delete removed ${200 - service.items.length} rows',
      );
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'after trim + Delete');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trim while an End request is pending: the focus ends on '
        'the new last row', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester);
      await focusTop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump(const Duration(milliseconds: 16));
      source.copy('fresh');
      await settle(tester);
      expect(focusedItem()?.id, service.items.last.id);
      expectFocusedOnScreen(tester, 'End + trim');
    });

    testWidgets('a trim while a Home request is pending (after End): the '
        'focus ends on a row, on screen', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester);
      await focusTop(tester);
      await key(tester, LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      source.copy('fresh');
      await settle(tester);
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'Home + copy');
    });

    testWidgets('a trim while an Up request into an unbuilt row is pending: '
        'no throw, the focus is on a row', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester, size: const Size(380, 260));
      await focusTop(tester);
      await key(tester, LogicalKeyboardKey.end);
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        source.copy('fresh $i');
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(focusedItem(), isNotNull);
      expectFocusedOnScreen(tester, 'Up + copies in a short window');
    });

    testWidgets('the trimmed focused item: the focus goes to the nearest '
        'remaining one and Delete removes exactly that one', (tester) async {
      useLimit(200);
      fill(200);
      await show(tester);
      await focusTop(tester);
      await key(tester, LogicalKeyboardKey.end);
      source.copy('fresh');
      await settle(tester);
      final now = focusedItem();
      expect(now, isNotNull);
      expect(now!.id, service.items.last.id, reason: 'nearest remaining');
      final before = service.items.length;
      await key(tester, LogicalKeyboardKey.delete);
      expect(service.items.length, before - 1);
      expect(service.items.any((i) => i.id == now.id), isFalse);
    });
  });

  group('the focused row is kept in view only while the arrow keys are '
      'in use', () {
    testWidgets('keyboard, wheel, keyboard: a copy after the wheel does not '
        'pull back; after the next arrow key it keeps the row in view', (
      tester,
    ) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await wheel(tester, 5000);
      final before = position(tester).pixels;
      source.copy('c2');
      await tester.pumpAndSettle();
      expect(
        position(tester).pixels,
        greaterThan(before - 400),
        reason: 'pulled back from $before',
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectFocusedOnScreen(tester, 'the next arrow key');
      source.copy('c3');
      await settle(tester);
      expectFocusedOnScreen(tester, 'a copy after the arrow key');
    });

    testWidgets('BUG-H7: a copy arrives while a row has the focus, then the '
        'user wheel-scrolls it away: the next arrow key must carry on (today '
        'no row has the focus and the keys are dead)', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      source.copy('c1');
      await settle(tester);
      expectFocusedOnScreen(tester, 'copy while the row has the focus');
      await wheel(tester, 5000);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedItem(), isNotNull, reason: 'the arrow key did nothing');
      expectFocusedOnScreen(tester, 'Down after copy + wheel');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectFocusedOnScreen(tester, 'second Down');
    });

    testWidgets('a click on a row, then copies: the focus stays on the '
        'clicked item and the list is not scrolled', (tester) async {
      fill(100);
      await show(tester);
      await focusTop(tester);
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.arrowDown);
      }
      final row = find.byKey(ValueKey('row-${service.items[5].id}'));
      await tester.tapAt(tester.getTopLeft(row) + const Offset(60, 16));
      await tester.pump();
      final clicked = focusedItem()!.id;
      final before = position(tester).pixels;
      for (var i = 0; i < 4; i++) {
        source.copy('fresh $i');
        await tester.pumpAndSettle();
      }
      expect(focusedItem()?.id, clicked);
      expect(position(tester).pixels, before);
    });

    testWidgets('a click, then the next arrow key turns following on '
        'again', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await wheel(tester, 5000);
      await key(tester, LogicalKeyboardKey.arrowDown); // following again
      source.copy('c');
      await settle(tester);
      expectFocusedOnScreen(tester, 'following after the arrow key');
    });

    testWidgets('a trackpad gesture still running (pan/zoom updates) when '
        'a copy arrives: the list is not pulled back', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      final pad = TestPointer(2, PointerDeviceKind.trackpad);
      final at = tester.getCenter(find.byType(CustomScrollView));
      await tester.sendEventToBinding(pad.panZoomStart(at));
      for (var i = 1; i <= 20; i++) {
        await tester.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(0, -200.0 * i)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      final before = position(tester).pixels;
      expect(before, greaterThan(1000));
      source.copy('during the gesture');
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        position(tester).pixels,
        greaterThan(before - 300),
        reason: 'pulled back during the gesture',
      );
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
    });

    testWidgets('a fling (momentum) still running when a copy arrives: it '
        'is not stopped or pulled back', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -600),
        2500,
      );
      await tester.pump(const Duration(milliseconds: 100));
      final before = position(tester).pixels;
      source.copy('during the fling');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        position(tester).pixels,
        greaterThanOrEqualTo(before),
        reason: 'the momentum was cut or reversed',
      );
      await tester.pumpAndSettle();
    });
  });
}
