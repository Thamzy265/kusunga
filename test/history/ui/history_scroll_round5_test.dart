import 'package:flutter/gestures.dart';
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

/// Tester round 5 on d966b6f (BUG-H7 fix: a row reads its node's focus state when it is created
/// and when its node changes). Breaking the fix: node swaps, theme and text
/// size changes, copies while the focus waits, clicks right after a copy.
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

  Future<void> settle(WidgetTester tester, [int max = 300]) async {
    var n = 0;
    while (tester.binding.hasScheduledFrame && n < max) {
      await tester.pump(const Duration(milliseconds: 16));
      n++;
    }
  }

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

  int indexOfId(int id) => service.items.indexWhere((e) => e.id == id);

  /// After [k] the focus must be on the neighbour of item [from] in the
  /// current list (previous = newer, next = older): never an unrelated row.
  void expectNeighbour(WidgetTester tester, int from, LogicalKeyboardKey k) {
    final i = indexOfId(from);
    expect(i, isNonNegative, reason: 'the source item is still there');
    final want = switch (k) {
      LogicalKeyboardKey.arrowUp => (i - 1).clamp(0, service.items.length - 1),
      LogicalKeyboardKey.arrowDown => (i + 1).clamp(
        0,
        service.items.length - 1,
      ),
      _ => i,
    };
    expect(
      focusedItem()?.id,
      service.items[want].id,
      reason:
          'focus landed on ${focusedText()}, expected '
          '${service.items[want].preview.split('\n').first}',
    );
    expectFocusedOnScreen(tester, 'after $k');
  }

  group('a focused row rebuilt at a new place, then disposed', () {
    for (final copies in [1, 3, 7]) {
      for (final k in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        testWidgets('$copies copies, wheel, ${k.keyLabel}: lands on the '
            'neighbour of the item that had the focus', (tester) async {
          fill(300);
          await show(tester);
          await focusTop(tester);
          for (var i = 0; i < 4; i++) {
            await key(tester, LogicalKeyboardKey.arrowDown);
          }
          final item = focusedItem()!.id;
          for (var i = 0; i < copies; i++) {
            source.copy('c$i');
            await tester.pumpAndSettle();
          }
          expect(focusedItem()?.id, item);
          await wheel(tester, 6000);
          await key(tester, k);
          expectNeighbour(tester, item, k);
        });
      }
    }

    testWidgets('copies arriving in bursts between wheel scrolls: every '
        'arrow key carries on from the same item', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      final item = focusedItem()!.id;
      for (var round = 0; round < 4; round++) {
        source.copy('a$round');
        source.copy('b$round');
        await tester.pumpAndSettle();
        await wheel(tester, round.isEven ? 6000 : -9000);
      }
      await key(tester, LogicalKeyboardKey.arrowUp);
      expectNeighbour(tester, item, LogicalKeyboardKey.arrowUp);
    });

    testWidgets('a copy arrives while the focus waits on the screen node: '
        'the next Up/Down still goes on from the same item', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.arrowDown);
      }
      final item = focusedItem()!.id;
      await wheel(tester, 6000);
      expect(focusedItem(), isNull);
      for (var i = 0; i < 5; i++) {
        source.copy('while waiting $i');
        await tester.pumpAndSettle();
        expect(focusedItem(), isNull, reason: 'copy $i gave a row the focus');
      }
      await key(tester, LogicalKeyboardKey.arrowUp);
      expectNeighbour(tester, item, LogicalKeyboardKey.arrowUp);
    });

    testWidgets('keys other than arrows do nothing while the focus waits '
        'and copies arrive', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await wheel(tester, 6000);
      source.copy('x');
      await tester.pumpAndSettle();
      final ids = [for (final i in service.items) i.id];
      for (final k in [
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyE,
      ]) {
        await key(tester, k);
      }
      expect([for (final i in service.items) i.id], ids);
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('rebuilt in place (theme, text size, window size)', () {
    Future<void> pumpApp(
      WidgetTester tester, {
      required Brightness brightness,
      required double scale,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: HistoryScreen(service: service),
        ),
      );
      await tester.pump();
    }

    testWidgets('a theme change and a text-size change while a row has the '
        'focus: it keeps the focus, and Down/Up and the wheel + Down still '
        'work', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      final item = focusedItem()!.id;
      await pumpApp(tester, brightness: Brightness.dark, scale: 1);
      expect(focusedItem()?.id, item, reason: 'theme change');
      await pumpApp(tester, brightness: Brightness.dark, scale: 2);
      expect(focusedItem()?.id, item, reason: 'text size change');
      await settle(tester);
      expectFocusedOnScreen(tester, 'after the text-size change');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectNeighbour(tester, item, LogicalKeyboardKey.arrowDown);
      final now = focusedItem()!.id;
      await pumpApp(tester, brightness: Brightness.light, scale: 1);
      source.copy('after theme');
      await tester.pumpAndSettle();
      await wheel(tester, 6000);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expectNeighbour(tester, now, LogicalKeyboardKey.arrowUp);
    });

    testWidgets('a text-size change while the focus waits on the screen '
        'node: the next arrow key still goes on from the item', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      final item = focusedItem()!.id;
      source.copy('c');
      await tester.pumpAndSettle();
      await wheel(tester, 6000);
      await pumpApp(tester, brightness: Brightness.light, scale: 2);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectNeighbour(tester, item, LogicalKeyboardKey.arrowDown);
    });

    testWidgets('a window resize while a row has the focus, a copy, then a '
        'wheel: arrow keys work', (tester) async {
      fill(300);
      await show(tester);
      await focusTop(tester);
      final item = focusedItem()!.id;
      tester.view.physicalSize = const Size(420, 300);
      await tester.pumpAndSettle();
      source.copy('c');
      await tester.pumpAndSettle();
      await wheel(tester, 6000);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectNeighbour(tester, item, LogicalKeyboardKey.arrowDown);
    });
  });

  group('clicking another row right after a copy', () {
    Future<void> clickRow(WidgetTester tester, int index) async {
      final row = find.byKey(ValueKey('row-${service.items[index].id}'));
      await tester.tapAt(tester.getTopLeft(row) + const Offset(60, 16));
      await tester.pump();
    }

    testWidgets('copy, click row 4 in the same frame as the copy lands: '
        'the clicked row has the focus, not the old one', (tester) async {
      fill(100);
      await show(tester);
      await focusTop(tester);
      source.copy('c');
      await clickRow(tester, 4); // before the copy's frames settle
      final clicked = focusedItem()!.id;
      expect(clicked, service.items[4].id);
      await tester.pumpAndSettle();
      expect(focusedItem()?.id, clicked, reason: 'the focus moved away');
      await wheel(tester, 5000);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expectNeighbour(tester, clicked, LogicalKeyboardKey.arrowUp);
    });

    testWidgets('copy, click another row, copy again, wheel, Down: the '
        'neighbour of the CLICKED row, not of the first one', (tester) async {
      fill(100);
      await show(tester);
      await focusTop(tester);
      final first = focusedItem()!.id;
      source.copy('c1');
      await tester.pumpAndSettle();
      await clickRow(tester, 6);
      final clicked = focusedItem()!.id;
      expect(clicked, isNot(first));
      source.copy('c2');
      await tester.pumpAndSettle();
      await wheel(tester, 5000);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectNeighbour(tester, clicked, LogicalKeyboardKey.arrowDown);
    });

    testWidgets('five quick copy + click pairs, then a wheel and an arrow '
        'key: the focus follows the last clicked item', (tester) async {
      fill(150);
      await show(tester);
      await focusTop(tester);
      late int last;
      for (var i = 0; i < 5; i++) {
        source.copy('q$i');
        await clickRow(tester, 3 + i);
        last = focusedItem()!.id;
      }
      await tester.pumpAndSettle();
      expect(focusedItem()?.id, last);
      await wheel(tester, 6000);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expectNeighbour(tester, last, LogicalKeyboardKey.arrowUp);
    });
  });

  group('HistoryRow in isolation: the disposal callback fires exactly when '
      'the row has the focus', () {
    ClipItem item(int id) => ClipItem(
      id: id,
      preview: 'x$id',
      kind: ClipKind.text,
      isTruncated: false,
      createdAt: 0,
      lastCopiedAt: 0,
    );

    Widget row(FocusNode node, int id, void Function() onGone) => MaterialApp(
      theme: KusungaTokens.themeData(Brightness.light),
      home: Scaffold(
        body: HistoryRow(
          key: ValueKey(id),
          item: item(id),
          focusNode: node,
          nowMs: 0,
          animateIn: false,
          autofocus: false,
          onCopy: () {},
          onDelete: () {},
          onMove: (_) {},
          onSaveAsSnippet: () {},
          canSaveAsSnippet: false,
          onDisposedWithFocus: onGone,
        ),
      ),
    );

    testWidgets('a row rebuilt at another place in the same frame, its node '
        'still focused: the new row reports its disposal too', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var gone = 0;
      Widget two(int id, {required bool second}) => MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              if (second) const SizedBox(height: 10),
              HistoryRow(
                key: ValueKey('r$id'),
                item: item(1),
                focusNode: node,
                nowMs: 0,
                animateIn: false,
                autofocus: false,
                onCopy: () {},
                onDelete: () {},
                onMove: (_) {},
                onSaveAsSnippet: () {},
                canSaveAsSnippet: false,
                onDisposedWithFocus: () => gone++,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(two(1, second: false));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      // A new key: the old element is disposed (gone 1) and a new row is
      // created in the same frame with the node still focused.
      await tester.pumpWidget(two(2, second: true));
      expect(gone, 1, reason: 'the first row had the focus when it went');
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(gone, 2, reason: 'the second row must report its disposal too');
    });

    testWidgets('a row without focus does not report its disposal', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var gone = 0;
      await tester.pumpWidget(row(node, 1, () => gone++));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(gone, 0);
    });

    testWidgets('a row given a new, focused node (same element) reports its '
        'disposal; one given a new unfocused node while the old one had '
        'focus does not', (tester) async {
      final a = FocusNode();
      final b = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      var gone = 0;
      await tester.pumpWidget(row(a, 1, () => gone++));
      a.requestFocus();
      await tester.pump();
      expect(a.hasFocus, isTrue);
      // Swap to an unfocused node: the row no longer has the focus.
      await tester.pumpWidget(row(b, 1, () => gone++));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(gone, 0, reason: 'the new node never had the focus');

      // Now the other way: swap to a node that already has the focus.
      final c = FocusNode();
      addTearDown(c.dispose);
      await tester.pumpWidget(row(c, 2, () => gone++));
      c.requestFocus();
      await tester.pump();
      final d = FocusNode();
      addTearDown(d.dispose);
      await tester.pumpWidget(row(d, 2, () => gone++));
      d.requestFocus();
      await tester.pump();
      expect(d.hasFocus, isTrue);
      await tester.pumpWidget(row(d, 2, () => gone++));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(gone, 1, reason: 'the row had the focus through node d');
    });

    testWidgets('focus lost by the user before disposal: not reported', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var gone = 0;
      await tester.pumpWidget(row(node, 1, () => gone++));
      node.requestFocus();
      await tester.pump();
      node.unfocus();
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(gone, 0);
    });
  });
}
