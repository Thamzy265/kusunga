import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../picker/fake_picker_port.dart';
import '../../support/fakes.dart';

void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController controller;

  setUp(() {
    port = FakePickerPort();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
    )..start();
    addTearDown(history.dispose);
  });

  void addSnippet(String name, String content, SnippetType type) =>
      history.snippets.save(name: name, content: content, type: type);

  Future<void> show(
    WidgetTester tester, {
    bool isMac = true,
    Size size = const Size(560, 420),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = PickerController(port: port, log: FakeLog(), isMac: isMac);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(history);
    port.press();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PickerPanel(controller: controller),
      ),
    );
    await tester.pump();
  }

  List<String> rowTexts(WidgetTester tester) => [
    for (final e in find.byKey(const ValueKey('picker-row-text')).evaluate())
      (e.widget as Text).textSpan!.toPlainText(),
  ];

  Future<void> switchTab(WidgetTester tester, {bool back = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Finder tab(String name) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == 'picker-tab-$name',
  );

  bool isSelected(WidgetTester tester, String name) =>
      tester.widget<Semantics>(tab(name)).properties.selected == true;

  testWidgets('opens on History always (D3), with both tabs', (tester) async {
    addSnippet('My mobile', '07700 900123', SnippetType.phone);
    source.copy('copied text');
    await show(tester);
    expect(isSelected(tester, 'history'), isTrue);
    expect(isSelected(tester, 'snippets'), isFalse);
    expect(rowTexts(tester), ['copied text']);
    expect(find.text('Search history…'), findsOneWidget);
  });

  testWidgets('Ctrl+Tab and Ctrl+Shift+Tab switch; focus stays in search', (
    tester,
  ) async {
    addSnippet('My mobile', '07700 900123', SnippetType.phone);
    addSnippet('Work email', 'will@example.com', SnippetType.email);
    source.copy('copied text');
    await show(tester);
    await switchTab(tester);
    expect(isSelected(tester, 'snippets'), isTrue);
    expect(rowTexts(tester), [
      'My mobile — 07700 900123',
      'Work email — will@example.com',
    ]);
    expect(find.text('Search snippets…'), findsOneWidget);
    expect(find.text('2 snippets'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    await switchTab(tester, back: true);
    expect(isSelected(tester, 'history'), isTrue);
    expect(rowTexts(tester), ['copied text']);
  });

  testWidgets('a click on a tab switches, and the search keeps focus', (
    tester,
  ) async {
    addSnippet('A', 'a', SnippetType.other);
    await show(tester);
    await tester.tap(tab('snippets'));
    await tester.pump();
    expect(isSelected(tester, 'snippets'), isTrue);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
  });

  testWidgets('switching keeps the query and filters the new tab by name '
      'and content', (tester) async {
    addSnippet('My mobile', '07700 900123', SnippetType.phone);
    addSnippet('Work email', 'will@example.com', SnippetType.email);
    source.copy('mobile in history');
    await show(tester);
    await tester.enterText(find.byType(TextField), 'mobile');
    await tester.pump();
    expect(rowTexts(tester), ['mobile in history']);
    await switchTab(tester);
    expect(rowTexts(tester), ['My mobile — 07700 900123']);
    expect(find.text('1 match'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'example');
    await tester.pump();
    expect(rowTexts(tester), ['Work email — will@example.com']);
  });

  testWidgets('Enter pastes the selected snippet, skipping history', (
    tester,
  ) async {
    addSnippet('My mobile', '07700 900123', SnippetType.phone);
    addSnippet('Work email', 'will@example.com', SnippetType.email);
    await show(tester);
    await switchTab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(port.pastes.single.text, 'will@example.com');
    expect(port.pastes.single.skipHistory, isTrue);
  });

  testWidgets('Cmd+1 quick-pastes the first snippet', (tester) async {
    addSnippet('My mobile', '07700 900123', SnippetType.phone);
    await show(tester);
    await switchTab(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(port.pastes.single.text, '07700 900123');
  });

  testWidgets('a snippet row is named "1, Phone, My mobile, 07700 900123"', (
    tester,
  ) async {
    addSnippet('My mobile', '07700 900123', SnippetType.phone);
    await show(tester);
    await switchTab(tester);
    final id = history.snippets.items.single.id;
    final row = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.identifier == 'picker-snippet-row-$id',
      ),
    );
    expect(row.properties.label, '1, Phone, My mobile, 07700 900123');
    expect(row.properties.selected, isTrue);
  });

  testWidgets('empty Snippets tab says how to add one', (tester) async {
    await show(tester);
    await switchTab(tester);
    expect(find.text('No snippets yet'), findsOneWidget);
    expect(find.text("Save one from Kusunga's main window."), findsOneWidget);
    expect(find.text('0 snippets'), findsOneWidget);
  });

  testWidgets('the footer shows the switch hint (Mac and Windows)', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('⌃Tab Switch'), findsOneWidget);
  });

  testWidgets('Windows hint is Ctrl+Tab Switch', (tester) async {
    await show(tester, isMac: false);
    expect(find.text('Ctrl+Tab Switch'), findsOneWidget);
  });

  testWidgets('the switch is announced on Windows: "Snippets, 2 items"', (
    tester,
  ) async {
    addSnippet('A', 'a', SnippetType.other);
    addSnippet('B', 'b', SnippetType.other);
    await show(tester, isMac: false);
    await switchTab(tester);
    final node = tester.widget<Semantics>(
      find.byKey(const ValueKey('picker-tab-announcement')),
    );
    expect(node.properties.liveRegion, isTrue);
    expect(node.properties.label, 'Snippets, 2 items');
  });

  testWidgets('a plain Tab still does nothing (focus stays in the search)', (
    tester,
  ) async {
    addSnippet('A', 'a', SnippetType.other);
    await show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(isSelected(tester, 'history'), isTrue);
  });

  testWidgets('a long snippet name and content fit on one line at 320 px', (
    tester,
  ) async {
    addSnippet('n' * 100, 'c' * 3000, SnippetType.other);
    await show(tester, size: const Size(320, 420));
    await switchTab(tester);
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('picker-row-text')),
    );
    expect(text.maxLines, 1);
  });
}
