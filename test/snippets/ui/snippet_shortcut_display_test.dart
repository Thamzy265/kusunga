// Shortcuts in the snippet list and the picker's Snippets tab (M1.5 UI spec,
// "Snippet list row" and "Picker snippet row"), and picker search.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippet_text.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../picker/fake_picker_port.dart';
import '../../support/fakes.dart';

const _item = SnippetItem(
  id: 1,
  name: 'Work email',
  type: SnippetType.email,
  preview: 'will@example.com',
  isTruncated: false,
  position: 0,
  createdAt: 1,
  updatedAt: 1,
  shortcut: ';email',
);

void main() {
  group('the shared texts', () {
    test('row, picker line and spoken names carry the shortcut', () {
      expect(snippetLine(_item), 'Work email ;email — will@example.com');
      expect(
        snippetRowName(_item),
        'Work email, Email, shortcut ;email, will@example.com',
      );
      expect(
        snippetPickerName(_item),
        'Email, Work email, shortcut ;email, will@example.com',
      );
    });

    test('without a shortcut nothing changes', () {
      const plain = SnippetItem(
        id: 2,
        name: 'My mobile',
        type: SnippetType.phone,
        preview: '07700 900123',
        isTruncated: false,
        position: 1,
        createdAt: 1,
        updatedAt: 1,
      );
      expect(snippetLine(plain), 'My mobile — 07700 900123');
      expect(snippetRowName(plain), 'My mobile, Phone, 07700 900123');
      expect(snippetPickerName(plain), 'Phone, My mobile, 07700 900123');
    });

    test('the picker line can leave the shortcut out (narrow picker)', () {
      expect(
        snippetLine(_item, withShortcut: false),
        'Work email — will@example.com',
      );
    });
  });

  group('main window list', () {
    late SnippetService service;

    setUp(() {
      service = SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      );
    });

    Future<void> show(WidgetTester tester, {double width = 800}) async {
      tester.view.physicalSize = Size(width, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: SnippetsScreen(service: service, now: () => 1000),
        ),
      );
      await tester.pump();
    }

    testWidgets('the shortcut follows the name in muted monospace, and the '
        'row is named with it', (tester) async {
      service.save(
        name: 'Work email',
        content: 'will@example.com',
        type: SnippetType.email,
        shortcut: ';email',
      );
      await show(tester);
      final text = tester.widget<Text>(find.text(';email'));
      final t = KusungaTokens.of(tester.element(find.text(';email')));
      expect(text.style!.fontFamily, KusungaTokens.mono.fontFamily);
      expect(text.style!.color, t.textMuted);
      final id = service.items.single.id;
      expect(
        tester
            .widget<Semantics>(
              find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.identifier == 'snippet-row-$id',
              ),
            )
            .properties
            .label,
        'Work email, Email, shortcut ;email, will@example.com',
      );
    });

    testWidgets('a long name is cut, the shortcut never is', (tester) async {
      service.save(
        name: 'A very long snippet name ' * 3,
        content: 'x',
        type: SnippetType.other,
        shortcut: ';' * 32,
      );
      await show(tester, width: 360);
      final box = tester.renderObject<RenderParagraph>(find.text(';' * 32));
      expect(box.didExceedMaxLines, isFalse);
      expect(
        tester.widget<Text>(find.text(';' * 32)).overflow,
        isNot(TextOverflow.ellipsis),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('picker Snippets tab', () {
    late HistoryService history;
    late PickerController controller;

    setUp(() {
      history = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: FakeLog(),
        snippetStore: MemorySnippetStore(),
      )..start();
      addTearDown(history.dispose);
    });

    Future<void> show(WidgetTester tester, {double width = 560}) async {
      tester.view.physicalSize = Size(width, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = FakePickerPort();
      controller = PickerController(port: port, log: FakeLog(), isMac: true);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(history);
      port.press();
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: PickerPanel(controller: controller),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    List<String> rowTexts(WidgetTester tester) => [
      for (final e in find.byKey(const ValueKey('picker-row-text')).evaluate())
        (e.widget as Text).textSpan!.toPlainText(),
    ];

    void addBoth() {
      history.snippets.save(
        name: 'Work email',
        content: 'will@example.com',
        type: SnippetType.email,
        shortcut: ';email',
      );
      history.snippets.save(
        name: 'My mobile',
        content: '07700 900123',
        type: SnippetType.phone,
      );
    }

    testWidgets('rows show "Name ;email — content" and are announced with '
        'the shortcut', (tester) async {
      addBoth();
      await show(tester);
      expect(rowTexts(tester), [
        'Work email ;email — will@example.com',
        'My mobile — 07700 900123',
      ]);
      final id = history.snippets.items.first.id;
      expect(
        tester
            .widget<Semantics>(
              find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.identifier == 'picker-snippet-row-$id',
              ),
            )
            .properties
            .label,
        startsWith('1, Email, Work email, shortcut ;email, will@example.com'),
      );
    });

    testWidgets('search matches the shortcut', (tester) async {
      addBoth();
      await show(tester);
      await tester.enterText(find.byType(TextField), ';ema');
      await tester.pump();
      expect(rowTexts(tester), ['Work email ;email — will@example.com']);
    });

    testWidgets('a changed shortcut is searchable at once', (tester) async {
      addBoth();
      await show(tester);
      final item = history.snippets.items.first;
      history.snippets.save(
        id: item.id,
        name: item.name,
        content: 'will@example.com',
        type: item.type,
        shortcut: ';work',
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), ';work');
      await tester.pump();
      expect(rowTexts(tester), ['Work email ;work — will@example.com']);
    });

    testWidgets('under 400 px the shortcut is dropped before the name is cut', (
      tester,
    ) async {
      addBoth();
      await show(tester, width: 380);
      expect(rowTexts(tester).first, 'Work email — will@example.com');
    });
  });
}
