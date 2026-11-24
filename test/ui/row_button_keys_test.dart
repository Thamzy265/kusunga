import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

/// BUG-K1 (tester round 9): a row's key handler is an ancestor of its
/// buttons, so Enter on a focused row button ran the row's Enter (Copy).
/// Enter and Space must activate the focused button; the row's Enter,
/// Delete, Backspace, S, E and F2 act only when the row itself has the
/// focus.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  final historyWrites = <String>[];

  setUp(() {
    historyWrites.clear();
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (text) async => historyWrites.add(text),
    )..start();
    addTearDown(service.dispose);
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> openSnippets(WidgetTester tester) async {
    await tester.tap(hook('main-tab-snippets'));
    await tester.pumpAndSettle();
  }

  /// Focuses the button behind the Semantics identifier [id].
  Future<void> focusButton(WidgetTester tester, String id) async {
    final inside = find.descendant(
      of: hook(id),
      matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
    );
    Focus.of(tester.element(inside.first)).requestFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> closeEditor(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.escape);
    expect(hook('snippet-editor'), findsNothing);
  }

  const keys = {
    'Enter': LogicalKeyboardKey.enter,
    'Space': LogicalKeyboardKey.space,
  };

  group('Snippets row buttons', () {
    late List<int> ids;

    setUp(() {
      for (var i = 1; i <= 5; i++) {
        service.snippets.save(
          name: 'snip $i',
          content: 'content $i',
          type: SnippetType.other,
        );
      }
      ids = [for (final s in service.snippets.items) s.id];
    });

    int indexOf(int id) => service.snippets.items.indexWhere((s) => s.id == id);

    keys.forEach((name, key) {
      testWidgets('$name on Copy copies', (tester) async {
        await show(tester);
        await openSnippets(tester);
        await focusButton(tester, 'snippet-copy-${ids[2]}');
        await press(tester, key);
        expect(source.ownWrites, ['content 3']);
        expect(service.snippets.items.length, 5);
      });

      testWidgets('$name on Edit opens the editor, copies nothing', (
        tester,
      ) async {
        await show(tester);
        await openSnippets(tester);
        await focusButton(tester, 'snippet-edit-${ids[2]}');
        await press(tester, key);
        expect(hook('snippet-editor'), findsOneWidget);
        expect(source.ownWrites, isEmpty);
        await closeEditor(tester);
      });

      testWidgets('$name on Move up moves it up, copies nothing', (
        tester,
      ) async {
        await show(tester);
        await openSnippets(tester);
        await focusButton(tester, 'snippet-up-${ids[2]}');
        await press(tester, key);
        expect(indexOf(ids[2]), 1);
        expect(source.ownWrites, isEmpty);
      });

      testWidgets('$name on Move down moves it down, copies nothing', (
        tester,
      ) async {
        await show(tester);
        await openSnippets(tester);
        await focusButton(tester, 'snippet-down-${ids[2]}');
        await press(tester, key);
        expect(indexOf(ids[2]), 3);
        expect(source.ownWrites, isEmpty);
      });

      testWidgets('$name on Delete deletes it, copies nothing', (tester) async {
        await show(tester);
        await openSnippets(tester);
        await focusButton(tester, 'snippet-delete-${ids[2]}');
        await press(tester, key);
        expect(indexOf(ids[2]), -1);
        expect(source.ownWrites, isEmpty);
      });

      testWidgets('520 px: $name on More opens the menu, copies nothing', (
        tester,
      ) async {
        await show(tester, size: const Size(520, 400));
        await openSnippets(tester);
        await focusButton(tester, 'snippet-more-${ids[2]}');
        await press(tester, key);
        expect(find.text('Move up'), findsOneWidget, reason: 'no menu');
        expect(source.ownWrites, isEmpty);
        await press(tester, LogicalKeyboardKey.escape);
      });
    });

    testWidgets('on the row itself: Enter copies, E and F2 edit, Delete and '
        'Backspace delete', (tester) async {
      await show(tester);
      await openSnippets(tester);
      Future<void> focusRow(int id) async {
        tester
            .widget<SnippetRow>(
              find.byWidgetPredicate((w) => w is SnippetRow && w.item.id == id),
            )
            .focusNode
            .requestFocus();
        await tester.pumpAndSettle();
      }

      await focusRow(ids[0]);
      await press(tester, LogicalKeyboardKey.enter);
      expect(source.ownWrites, ['content 1']);
      for (final k in [LogicalKeyboardKey.keyE, LogicalKeyboardKey.f2]) {
        await focusRow(ids[0]);
        await press(tester, k);
        expect(hook('snippet-editor'), findsOneWidget, reason: '$k');
        await closeEditor(tester);
      }
      await focusRow(ids[1]);
      await press(tester, LogicalKeyboardKey.delete);
      expect(indexOf(ids[1]), -1);
      await focusRow(ids[3]);
      await press(tester, LogicalKeyboardKey.backspace);
      expect(indexOf(ids[3]), -1);
    });
  });

  group('History row buttons', () {
    late List<int> ids;

    setUp(() {
      for (var i = 1; i <= 5; i++) {
        source.copy('history item $i');
      }
      ids = [for (final e in service.items) e.id];
    });

    bool has(int id) => service.items.any((e) => e.id == id);

    keys.forEach((name, key) {
      testWidgets('$name on Copy copies', (tester) async {
        await show(tester);
        await focusButton(tester, 'history-copy-${ids[2]}');
        await press(tester, key);
        expect(historyWrites, [service.textOf(ids[2])]);
        expect(service.items.length, 5);
      });

      testWidgets('$name on Save as snippet opens the editor, copies '
          'nothing', (tester) async {
        await show(tester);
        await focusButton(tester, 'history-save-snippet-${ids[2]}');
        await press(tester, key);
        expect(hook('snippet-editor'), findsOneWidget);
        expect(historyWrites, isEmpty);
        await closeEditor(tester);
      });

      testWidgets('$name on Delete deletes it, copies nothing', (tester) async {
        await show(tester);
        await focusButton(tester, 'history-delete-${ids[2]}');
        await press(tester, key);
        expect(has(ids[2]), isFalse);
        expect(historyWrites, isEmpty);
      });
    });

    testWidgets('on the row itself: Enter copies, S saves as snippet, Delete '
        'and Backspace delete', (tester) async {
      await show(tester);
      Future<void> focusRow(int id) async {
        tester
            .widget<HistoryRow>(
              find.byWidgetPredicate((w) => w is HistoryRow && w.item.id == id),
            )
            .focusNode
            .requestFocus();
        await tester.pumpAndSettle();
      }

      await focusRow(ids[0]);
      await press(tester, LogicalKeyboardKey.enter);
      expect(historyWrites, [service.textOf(ids[0])]);
      await focusRow(ids[0]);
      await press(tester, LogicalKeyboardKey.keyS);
      expect(hook('snippet-editor'), findsOneWidget);
      await closeEditor(tester);
      await focusRow(ids[1]);
      await press(tester, LogicalKeyboardKey.delete);
      expect(has(ids[1]), isFalse);
      await focusRow(ids[3]);
      await press(tester, LogicalKeyboardKey.backspace);
      expect(has(ids[3]), isFalse);
    });
  });
}
