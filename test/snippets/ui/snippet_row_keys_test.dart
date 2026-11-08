import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';

/// QA-M14-2: Up/Down move the focus between snippet rows, as in the History
/// list (with Home/End and Cmd+Up/Down for the first and last row).
///
/// The real app only draws a frame when something asks for one. A focus
/// move that waits for "the next frame" never happens after a plain key
/// press, so these tests check the focus right after the key, before any
/// pump.
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

  void add(String name) =>
      service.save(name: name, content: '$name text', type: SnippetType.other);

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: SnippetsScreen(service: service, now: () => 0),
      ),
    );
    await tester.pump();
  }

  bool focused(WidgetTester tester, String name) =>
      Focus.of(tester.element(find.text(name))).hasPrimaryFocus;

  Future<void> click(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump();
    expect(focused(tester, name), isTrue);
  }

  testWidgets('Down and Up move the focus at once, without waiting for a '
      'frame', (tester) async {
    add('A');
    add('B');
    add('C');
    await show(tester);
    await click(tester, 'A');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(focused(tester, 'B'), isTrue, reason: 'Down from A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(focused(tester, 'C'), isTrue, reason: 'Down from B');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(focused(tester, 'B'), isTrue, reason: 'Up from C');
    // The ring follows the focus on the next frame.
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('Up on the first row and Down on the last stay put', (
    tester,
  ) async {
    add('A');
    add('B');
    await show(tester);
    await click(tester, 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focused(tester, 'A'), isTrue);
    await click(tester, 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, 'B'), isTrue);
    expect(service.items.map((s) => s.name), ['A', 'B'], reason: 'no move');
  });

  testWidgets('Home and End go to the first and last row', (tester) async {
    add('A');
    add('B');
    add('C');
    await show(tester);
    await click(tester, 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(focused(tester, 'C'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(focused(tester, 'A'), isTrue);
  });

  testWidgets('Cmd+Down and Cmd+Up go to the last and first row (Mac)', (
    tester,
  ) async {
    add('A');
    add('B');
    add('C');
    await show(tester);
    await click(tester, 'B');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(focused(tester, 'C'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(focused(tester, 'A'), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(service.items.map((s) => s.name), [
      'A',
      'B',
      'C',
    ], reason: 'no move');
  });

  testWidgets('End in a long list scrolls the last row into view and '
      'focuses it', (tester) async {
    for (var i = 0; i < 60; i++) {
      add('Snippet $i');
    }
    await show(tester);
    await click(tester, 'Snippet 0');
    expect(find.text('Snippet 59'), findsNothing, reason: 'not built yet');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.pump();
    expect(focused(tester, 'Snippet 59'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.pump();
    expect(focused(tester, 'Snippet 0'), isTrue);
  });

  testWidgets('a snippet saved while a row deep in the list has the focus '
      '(it is added at the end) leaves the focus on that row, on screen '
      '(the Snippets side of BUG-H3)', (tester) async {
    for (var i = 0; i < 60; i++) {
      add('Snippet $i');
    }
    await show(tester);
    await click(tester, 'Snippet 0');
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(focused(tester, 'Snippet 20'), isTrue);
    for (var i = 0; i < 5; i++) {
      add('New $i');
      await tester.pump();
      expect(focused(tester, 'Snippet 20'), isTrue, reason: 'after New $i');
    }
    final row = tester.getRect(find.text('Snippet 20'));
    final view = tester.getRect(find.byType(CustomScrollView));
    expect(row.top >= view.top && row.bottom <= view.bottom, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, 'Snippet 21'), isTrue);
  });
}
