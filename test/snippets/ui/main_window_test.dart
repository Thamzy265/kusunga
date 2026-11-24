import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:kusunga/snippets/ui/snippet_editor.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late MemorySnippetStore snippets;
  late HistoryService service;

  HistoryService make({Set<HistoryNotice> notices = const {}}) {
    final s = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      notices: notices,
      snippetStore: snippets,
    )..start();
    addTearDown(s.dispose);
    return s;
  }

  setUp(() {
    source = FakeClipboardSource();
    snippets = MemorySnippetStore();
  });

  Future<void> show(
    WidgetTester tester, {
    Future<HistoryService>? history,
    Size size = const Size(800, 632),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: HistoryHost(history: history ?? Future.value(service)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  bool selected(WidgetTester tester, String id) =>
      tester.widget<Semantics>(hook(id)).properties.selected == true;

  Future<void> openSnippets(WidgetTester tester) async {
    await tester.tap(hook('main-tab-snippets'));
    await tester.pump();
  }

  group('tabs', () {
    testWidgets('History is selected at start; Snippets shows the list', (
      tester,
    ) async {
      service = make();
      source.copy('copied');
      await show(tester);
      expect(selected(tester, 'main-tab-history'), isTrue);
      expect(find.text('copied'), findsOneWidget);
      expect(find.text('No snippets yet'), findsNothing);
      await openSnippets(tester);
      expect(selected(tester, 'main-tab-snippets'), isTrue);
      expect(find.text('No snippets yet'), findsOneWidget);
      expect(find.text('copied'), findsNothing);
    });

    testWidgets('Left and Right move between the tabs', (tester) async {
      service = make();
      await show(tester);
      await tester.tap(hook('main-tab-history'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'main-tab-snippets'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(selected(tester, 'main-tab-history'), isTrue);
    });

    testWidgets('the history keeps its state while Snippets shows', (
      tester,
    ) async {
      service = make();
      source.copy('a');
      source.copy('b');
      await show(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
      await tester.pump();
      await openSnippets(tester);
      await tester.tap(hook('main-tab-history'));
      await tester.pump();
      expect(service.items.length, 1);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('360 px at 200% text: tabs and New wrap, no overflow', (
      tester,
    ) async {
      service = make();
      await show(tester, size: const Size(360, 400), textScale: 2);
      await openSnippets(tester);
      expect(tester.takeException(), isNull);
      expect(hook('snippet-new'), findsOneWidget);
    });
  });

  group('New snippet', () {
    testWidgets('only on the Snippets tab; opens the editor', (tester) async {
      service = make();
      await show(tester);
      expect(hook('snippet-new'), findsNothing);
      await openSnippets(tester);
      await tester.tap(hook('snippet-new'));
      await tester.pumpAndSettle();
      expect(find.text('New snippet'), findsWidgets);
      expect(hook('snippet-editor'), findsOneWidget);
    });

    testWidgets('off in memory-only mode, with the banner', (tester) async {
      service = make(notices: {HistoryNotice.memoryOnly});
      await show(tester);
      await openSnippets(tester);
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: hook('snippet-new'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining("Snippets can't be opened right now"),
        findsOneWidget,
      );
    });

    testWidgets('off at 1,000 snippets, with the reason as text', (
      tester,
    ) async {
      for (var i = 0; i < SnippetStore.maxCount; i++) {
        snippets.insert(
          name: 's$i',
          content: 'c',
          type: SnippetType.other,
          nowMs: i,
        );
      }
      service = make();
      await show(tester);
      await openSnippets(tester);
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: hook('snippet-new'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text(snippetCapMessage), findsOneWidget);
    });
  });

  group('loading', () {
    testWidgets('"Opening your snippets…" only after 300 ms', (tester) async {
      final opening = Completer<HistoryService>();
      await show(tester, history: opening.future);
      await openSnippets(tester);
      expect(find.text('Opening your snippets…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Opening your snippets…'), findsOneWidget);
      await tester.tap(hook('main-tab-history'));
      await tester.pump();
      expect(find.text('Opening your history…'), findsOneWidget);
      service = make();
      opening.complete(service);
      await tester.pump();
      await tester.pump();
      expect(find.text('Opening your history…'), findsNothing);
    });
  });

  group('Save as snippet (history row)', () {
    Finder historyField(String id) =>
        find.descendant(of: hook(id), matching: find.byType(TextField));

    testWidgets('between Copy and Delete; opens the editor filled in; the '
        'history item stays (D2)', (tester) async {
      service = make();
      source.copy('07700 900123\nmobile');
      await show(tester);
      final id = service.items.single.id;
      final copyX = tester.getCenter(hook('history-copy-$id')).dx;
      final saveX = tester.getCenter(hook('history-save-snippet-$id')).dx;
      final deleteX = tester.getCenter(hook('history-delete-$id')).dx;
      expect(copyX, lessThan(saveX));
      expect(saveX, lessThan(deleteX));

      await tester.tap(hook('history-save-snippet-$id'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(historyField('snippet-editor-name'))
            .controller!
            .text,
        '07700 900123',
      );
      expect(
        tester
            .widget<TextField>(historyField('snippet-editor-content'))
            .controller!
            .text,
        '07700 900123\nmobile',
      );
      await tester.tap(hook('snippet-editor-save'));
      await tester.pumpAndSettle();
      expect(find.text('Snippet saved'), findsOneWidget);
      expect(service.snippets.items.single.name, '07700 900123');
      expect(service.items.length, 1, reason: 'pinning copies (D2)');
    });

    testWidgets('S on the focused history row opens the editor', (
      tester,
    ) async {
      service = make();
      source.copy('pin me');
      await show(tester);
      await tester.tap(find.text('pin me'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(hook('snippet-editor'), findsOneWidget);
    });

    testWidgets('off in memory-only mode', (tester) async {
      service = make(notices: {HistoryNotice.memoryOnly});
      source.copy('x');
      await show(tester);
      final id = service.items.single.id;
      expect(
        tester
            .widget<Semantics>(hook('history-save-snippet-$id'))
            .properties
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('x'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(hook('snippet-editor'), findsNothing);
    });

    testWidgets('off at the cap; S explains why', (tester) async {
      for (var i = 0; i < SnippetStore.maxCount; i++) {
        snippets.insert(
          name: 's$i',
          content: 'c',
          type: SnippetType.other,
          nowMs: i,
        );
      }
      service = make();
      source.copy('x');
      await show(tester);
      final id = service.items.single.id;
      expect(
        tester
            .widget<Semantics>(hook('history-save-snippet-$id'))
            .properties
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('x'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(find.text(snippetCapMessage), findsOneWidget);
      expect(hook('snippet-editor'), findsNothing);
    });
  });
}
