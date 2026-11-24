import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';

/// Tester round 2 on c933c6f (Snippets: prototype-extent list, scroll by
/// index): a reorder while scrolled, the 1,000-snippet cap with End/Home
/// (frames counted), rows with very different content, and a resize.
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

  String? focusedName() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    String? name;
    if (ctx.widget is SnippetRow) return (ctx.widget as SnippetRow).item.name;
    ctx.visitAncestorElements((e) {
      if (e.widget is SnippetRow) {
        name = (e.widget as SnippetRow).item.name;
        return false;
      }
      return true;
    });
    return name;
  }

  bool onScreen(WidgetTester tester, String name) {
    final f = find.text(name);
    if (f.evaluate().isEmpty) return false;
    final row = tester.getRect(f);
    final view = tester.getRect(find.byType(CustomScrollView));
    return row.top >= view.top - 0.5 && row.bottom <= view.bottom + 0.5;
  }

  Future<int> framesAfter(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    var n = 0;
    while (tester.binding.hasScheduledFrame && n < 500) {
      await tester.pump(const Duration(milliseconds: 16));
      n++;
    }
    return n;
  }

  Future<void> altKey(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    var n = 0;
    while (tester.binding.hasScheduledFrame && n < 200) {
      await tester.pump(const Duration(milliseconds: 16));
      n++;
    }
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

  Future<void> click(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump();
    expect(focusedName(), name);
  }

  testWidgets('a reorder while scrolled: Alt+Down 8 times in the middle of '
      '200 rows keeps the focus on the moved row, on screen', (tester) async {
    fill(200);
    await show(tester);
    await scrollTo(tester, 'Snippet 100');
    await click(tester, 'Snippet 100');
    for (var i = 1; i <= 8; i++) {
      await altKey(tester, LogicalKeyboardKey.arrowDown);
      expect(service.items[100 + i].name, 'Snippet 100', reason: 'moved $i');
      expect(focusedName(), 'Snippet 100', reason: 'focus after move $i');
      expect(onScreen(tester, 'Snippet 100'), isTrue, reason: 'move $i');
    }
    for (var i = 1; i <= 12; i++) {
      await altKey(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedName(), 'Snippet 100', reason: 'focus after up $i');
      expect(onScreen(tester, 'Snippet 100'), isTrue, reason: 'up $i');
    }
    expect(service.items[96].name, 'Snippet 100');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reorder of the row at the very top edge of the viewport '
      'upwards (it moves out of view and is brought back)', (tester) async {
    fill(120);
    await show(tester);
    await scrollTo(tester, 'Snippet 60');
    await click(tester, 'Snippet 60');
    // Make it the top row of the viewport by moving it up one at a time.
    for (var i = 0; i < 6; i++) {
      await altKey(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedName(), 'Snippet 60');
      expect(onScreen(tester, 'Snippet 60'), isTrue, reason: 'up $i');
    }
  });

  testWidgets('a reorder with the Move down button, at 200% text, at the '
      'bottom of the list', (tester) async {
    fill(60);
    await show(tester, textScale: 2);
    await scrollTo(tester, 'Snippet 57');
    await click(tester, 'Snippet 57');
    for (var i = 0; i < 2; i++) {
      await altKey(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(service.items.last.name, 'Snippet 57');
    expect(focusedName(), 'Snippet 57');
    expect(onScreen(tester, 'Snippet 57'), isTrue);
    await altKey(tester, LogicalKeyboardKey.arrowDown); // already last
    expect(focusedName(), 'Snippet 57');
  });

  testWidgets('the 1,000 snippet cap: End and Home are bounded in frames, '
      'land on the right row, on screen; Up/Down go on from there', (
    tester,
  ) async {
    fill(1000);
    await show(tester);
    await tester.tap(find.text('Snippet 0'));
    await tester.pump();
    final end = await framesAfter(tester, LogicalKeyboardKey.end);
    // ignore: avoid_print
    print('FRAMES snippets End in 1000: $end');
    expect(end, lessThan(30), reason: 'End took $end frames');
    expect(focusedName(), 'Snippet 999');
    expect(onScreen(tester, 'Snippet 999'), isTrue);
    await framesAfter(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedName(), 'Snippet 999');
    for (var i = 1; i <= 15; i++) {
      await framesAfter(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedName(), 'Snippet ${999 - i}');
      expect(onScreen(tester, 'Snippet ${999 - i}'), isTrue);
    }
    final home = await framesAfter(tester, LogicalKeyboardKey.home);
    // ignore: avoid_print
    print('FRAMES snippets Home in 1000: $home');
    expect(home, lessThan(30));
    expect(focusedName(), 'Snippet 0');
    expect(onScreen(tester, 'Snippet 0'), isTrue);
    await framesAfter(tester, LogicalKeyboardKey.end);
    expect(focusedName(), 'Snippet 999');
  });

  testWidgets('every row has one height whatever it holds (the list assumes '
      'it): a 100-character name, three lines of content, and CJK', (
    tester,
  ) async {
    service.save(name: 'a', content: 'x', type: SnippetType.other);
    service.save(name: 'N' * 100, content: 'y', type: SnippetType.other);
    service.save(
      name: 'multi',
      content: 'l1\nl2\nl3\n${'z' * 300}',
      type: SnippetType.address,
    );
    service.save(name: '日本語の名前', content: '電話番号', type: SnippetType.phone);
    for (final scale in [1.0, 2.0]) {
      await show(tester, textScale: scale);
      final heights = <double>{
        for (final s in service.items)
          tester
              .getRect(find.byKey(ValueKey('snippet-row-box-${s.id}')))
              .height,
      };
      expect(heights, hasLength(1), reason: '$scale: $heights');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a resize during navigation: the focused row is on screen in '
      'the new window, and Down goes on', (tester) async {
    fill(200);
    await show(tester);
    await tester.tap(find.text('Snippet 0'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await framesAfter(tester, LogicalKeyboardKey.arrowDown);
    }
    tester.view.physicalSize = const Size(380, 260);
    await tester.pumpAndSettle();
    for (var i = 7; i <= 25; i++) {
      await framesAfter(tester, LogicalKeyboardKey.arrowDown);
      expect(tester.takeException(), isNull, reason: 'Down to $i');
      expect(focusedName(), 'Snippet $i');
      expect(onScreen(tester, 'Snippet $i'), isTrue, reason: 'Snippet $i');
    }
    await framesAfter(tester, LogicalKeyboardKey.end);
    expect(focusedName(), 'Snippet 199');
    expect(onScreen(tester, 'Snippet 199'), isTrue);
  });

  testWidgets('a delete at the end of a long list, then Undo: the focus is '
      'on a visible row and End still works', (tester) async {
    fill(300);
    await show(tester);
    await tester.tap(find.text('Snippet 0'));
    await tester.pump();
    await framesAfter(tester, LogicalKeyboardKey.end);
    await framesAfter(tester, LogicalKeyboardKey.delete);
    expect(focusedName(), 'Snippet 298');
    expect(onScreen(tester, 'Snippet 298'), isTrue);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(service.items.last.name, 'Snippet 299');
    await tester.tap(find.text('Snippet 298'));
    await tester.pump();
    await framesAfter(tester, LogicalKeyboardKey.end);
    expect(focusedName(), 'Snippet 299');
    expect(onScreen(tester, 'Snippet 299'), isTrue);
  });
}
