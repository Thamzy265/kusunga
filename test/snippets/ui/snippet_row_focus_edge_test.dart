import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';

/// Tester probes for QA-M14-2 (3b7ada6): Up/Down, Home/End and Cmd+Up/Down
/// on very long lazily built lists, at 200% text, and after a delete, a
/// reorder and an Undo. The focus must follow the key at once (no frame is
/// scheduled by a key press) and the focused row must be on screen (WCAG
/// 2.4.11).
void main() {
  late SnippetService service;

  setUp(() {
    service = SnippetService(
      store: FlakySnippetStore(),
      log: FakeLog(),
      editable: true,
      clock: () => 0,
      writeClipboard: (_) async => true,
    );
  });

  void fill(int n) {
    for (var i = 0; i < n; i++) {
      service.save(
        name: 'Snippet $i',
        content: 'content $i',
        type: SnippetType.other,
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
        home: SnippetsScreen(service: service, now: () => 0),
      ),
    );
    await tester.pump();
  }

  /// The name of the snippet row that has the focus (or holds it, for a row
  /// button), or null when no row does.
  String? focusedName(WidgetTester tester) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    String? name;
    if (ctx.widget is SnippetRow) {
      name = (ctx.widget as SnippetRow).item.name;
    } else {
      ctx.visitAncestorElements((e) {
        if (e.widget is SnippetRow) {
          name = (e.widget as SnippetRow).item.name;
          return false;
        }
        return true;
      });
    }
    return name;
  }

  bool focused(WidgetTester tester, String name) => focusedName(tester) == name;

  Future<void> click(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump();
    expect(focused(tester, name), isTrue);
  }

  Future<void> scrollTo(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(
      find.text(name),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 400,
    );
    await tester.pumpAndSettle();
  }

  /// True when the row with [name] lies inside the scrolling viewport.
  bool onScreen(WidgetTester tester, String name) {
    final row = tester.getRect(find.text(name));
    final view = tester.getRect(find.byType(CustomScrollView));
    return row.top >= view.top - 0.5 && row.bottom <= view.bottom + 0.5;
  }

  group('very long lists', () {
    testWidgets('End, Home, End: the focus lands on the right row each time, '
        'with one pump per key', (tester) async {
      fill(1000);
      await show(tester);
      await click(tester, 'Snippet 0');
      for (final (key, name) in [
        (LogicalKeyboardKey.end, 'Snippet 999'),
        (LogicalKeyboardKey.home, 'Snippet 0'),
        (LogicalKeyboardKey.end, 'Snippet 999'),
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(focusedName(tester), name, reason: '$key');
        expect(onScreen(tester, name), isTrue, reason: '$name is on screen');
      }
    });

    testWidgets(
      'BUG-U1: End in a 1,000 list does not scroll past the end first '
      '(the jump uses an estimated extent that is 2,000 px too long, so '
      'for a moment the list shows empty space and the focused row is '
      'off screen)',
      (tester) async {
        fill(1000);
        await show(tester);
        await click(tester, 'Snippet 0');
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        await tester.pump();
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(
          position.pixels,
          lessThanOrEqualTo(position.maxScrollExtent + 1),
        );
      },
    ); // BUG-U1: End/Home jump to an estimated maxScrollExtent

    testWidgets('BUG-U2: End then Home with no frame between ends on the '
        'first row (the End waits for a frame to focus the last row, and '
        'then takes the focus back from Home)', (tester) async {
      fill(400);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 0');
    }); // BUG-U2

    testWidgets('Cmd+Down in a 1,000 list reaches the last row', (
      tester,
    ) async {
      fill(1000);
      await show(tester);
      await click(tester, 'Snippet 3');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump();
      expect(focusedName(tester), 'Snippet 999');
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('Down 3 times from the top at ${scale * 100}% text: the '
          'focus follows every key at once', (tester) async {
        fill(60);
        await show(tester, textScale: scale);
        await click(tester, 'Snippet 0');
        for (var i = 1; i <= 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          expect(focusedName(tester), 'Snippet $i', reason: 'Down #$i');
          await tester.pump();
        }
      });

      testWidgets('BUG-U3: Down 30 times from the top of a 60-row list at '
          '${scale * 100}% text: each focused row is scrolled into view '
          '(today the focus walks off the bottom, then the list jumps to '
          'its end and the focus is lost)', (tester) async {
        fill(60);
        await show(tester, textScale: scale);
        await click(tester, 'Snippet 0');
        for (var i = 1; i <= 30; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.pump();
          expect(focusedName(tester), 'Snippet $i', reason: 'Down #$i');
          expect(
            onScreen(tester, 'Snippet $i'),
            isTrue,
            reason: 'Snippet $i is not on screen',
          );
        }
      }); // BUG-U3
    }

    testWidgets('BUG-U3: Up 40 times after End walks back up, each row '
        'scrolled into view', (tester) async {
      fill(100);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.pump();
      for (var i = 1; i <= 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(focusedName(tester), 'Snippet ${99 - i}', reason: 'Up #$i');
        expect(onScreen(tester, 'Snippet ${99 - i}'), isTrue);
      }
    }); // BUG-U3

    testWidgets('Home from the middle of a scrolled long list', (tester) async {
      fill(400);
      await show(tester);
      await scrollTo(tester, 'Snippet 200');
      await click(tester, 'Snippet 200');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 0');
      expect(onScreen(tester, 'Snippet 0'), isTrue);
    });

    testWidgets('Up and Down from a row in the middle of a long list '
        'move to its neighbours', (tester) async {
      fill(400);
      await show(tester);
      await scrollTo(tester, 'Snippet 200');
      await click(tester, 'Snippet 200');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(focusedName(tester), 'Snippet 201');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(focusedName(tester), 'Snippet 199');
    });

    testWidgets('a short window (one row high) and 200% text still move the '
        'focus on End', (tester) async {
      fill(300);
      await show(tester, textScale: 2, size: const Size(400, 220));
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.pump();
      expect(focusedName(tester), 'Snippet 299');
      expect(tester.takeException(), isNull);
    });
  });

  group('after a delete', () {
    testWidgets('Delete moves the focus to the next row, and Down/Up go on '
        'from there', (tester) async {
      fill(5);
      await show(tester);
      await click(tester, 'Snippet 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 2');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(focusedName(tester), 'Snippet 3');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(
        focusedName(tester),
        'Snippet 0',
        reason: 'Snippet 1 is gone, so Up from 2 is 0',
      );
    });

    testWidgets('deleting the last row focuses the previous one', (
      tester,
    ) async {
      fill(3);
      await show(tester);
      await click(tester, 'Snippet 2');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(focusedName(tester), 'Snippet 1', reason: 'End is the new last');
    });

    testWidgets('deleting the only row leaves nothing to move, and keys do '
        'not throw', (tester) async {
      fill(1);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ]) {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(service.items, isEmpty);
    });

    testWidgets('delete in a 400-row list after End: focus goes to the new '
        'last row and is on screen', (tester) async {
      fill(400);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 398');
      expect(onScreen(tester, 'Snippet 398'), isTrue);
    });

    testWidgets('delete of a row far down (scrolled to by the mouse wheel): '
        'the next row is focused and on screen, and Up still moves', (
      tester,
    ) async {
      fill(400);
      await show(tester);
      await scrollTo(tester, 'Snippet 80');
      await click(tester, 'Snippet 80');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 81');
      expect(onScreen(tester, 'Snippet 81'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(focusedName(tester), 'Snippet 79');
    });

    testWidgets('two deletes in a row (the second before the first '
        'toast ends) keep the focus on a row', (tester) async {
      fill(4);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(service.items.map((s) => s.name), ['Snippet 2', 'Snippet 3']);
      expect(focusedName(tester), 'Snippet 2');
    });
  });

  group('after a reorder', () {
    testWidgets('Alt+Down keeps the focus on the moved row, and Down then '
        'goes to the new neighbour', (tester) async {
      fill(4);
      await show(tester);
      await click(tester, 'Snippet 1');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(service.items.map((s) => s.name), [
        'Snippet 0',
        'Snippet 2',
        'Snippet 1',
        'Snippet 3',
      ]);
      expect(focusedName(tester), 'Snippet 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(focusedName(tester), 'Snippet 3');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(focusedName(tester), 'Snippet 2', reason: 'new order');
    });

    testWidgets('Alt+Up on the first row and Alt+Down on the last move '
        'nothing and keep the focus', (tester) async {
      fill(3);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 0');
      await click(tester, 'Snippet 2');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 2');
      expect(service.items.map((s) => s.name), [
        'Snippet 0',
        'Snippet 1',
        'Snippet 2',
      ]);
    });

    testWidgets('BUG-U3: Alt+Down 40 times in a long list carries the row '
        '(and the focus) down past the viewport', (tester) async {
      fill(200);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(service.items[40].name, 'Snippet 0');
      expect(focusedName(tester), 'Snippet 0');
      expect(onScreen(tester, 'Snippet 0'), isTrue);
    }); // BUG-U3

    testWidgets('moving the first row to the bottom of a 400-row list with '
        'Alt+Down then End keeps the focus on a real row', (tester) async {
      fill(400);
      await show(tester);
      await click(tester, 'Snippet 0');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.pump();
      expect(focusedName(tester), 'Snippet 399');
    });
  });

  group('after Undo', () {
    testWidgets('Undo by mouse: the row comes back in its place and the '
        'keys still move the focus', (tester) async {
      fill(4);
      await show(tester);
      await click(tester, 'Snippet 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(service.items.map((s) => s.name), [
        'Snippet 0',
        'Snippet 1',
        'Snippet 2',
        'Snippet 3',
      ]);
      // A click on a row (the next thing a mouse user does) works, and Down
      // moves from it.
      await click(tester, 'Snippet 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(focusedName(tester), 'Snippet 1', reason: 'restored row');
    });

    testWidgets('Undo by keyboard (focus on the Undo button, Enter): the '
        'focus is not lost, it ends on a snippet row', (tester) async {
      fill(4);
      await show(tester);
      await click(tester, 'Snippet 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Undo'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.items, hasLength(4));
      // A keyboard user has nowhere to go if the focus fell off the screen.
      expect(
        focusedName(tester),
        isNotNull,
        reason: 'after Undo no snippet row has the focus: Up/Down are dead',
      );
    });

    testWidgets('Undo of the last row, then End, focuses the restored row', (
      tester,
    ) async {
      fill(3);
      await show(tester);
      await click(tester, 'Snippet 2');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 1');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await click(tester, 'Snippet 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(focusedName(tester), 'Snippet 2');
    });

    testWidgets('delete, Undo, delete again: no stale focus node throws', (
      tester,
    ) async {
      fill(3);
      await show(tester);
      await click(tester, 'Snippet 1');
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        await click(tester, 'Snippet 1');
      }
      expect(tester.takeException(), isNull);
      expect(service.items, hasLength(3));
    });

    testWidgets('Undo of a delete in a long list restores the row at its '
        'index and the list is still navigable with End', (tester) async {
      fill(500);
      await show(tester);
      await scrollTo(tester, 'Snippet 30');
      await click(tester, 'Snippet 30');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(service.items[30].name, 'Snippet 30');
      await click(tester, 'Snippet 31');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(focusedName(tester), 'Snippet 30', reason: 'the restored row');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(focusedName(tester), 'Snippet 499');
    });
  });
}
