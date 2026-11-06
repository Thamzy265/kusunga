import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

/// QA-M14-7: a count of 1 takes the singular ("1 older item will be
/// deleted.", "Delete 1 item"); 2 or more keep the plural. Every count
/// string in the main window that can be 1 is checked here. (The History
/// limit is at least 10, so "N of L items" and "Keep only the newest N
/// items?" are never singular.)
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  setUp(() {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
  });

  void copies(int n) {
    for (var i = 1; i <= n; i++) {
      source.copy('item $i');
    }
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 632);
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

  Future<void> lowerLimitTo10(WidgetTester tester) async {
    final field = find.descendant(
      of: find.byType(LimitField),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  group('History: lowering the limit', () {
    testWidgets('1 to delete: "1 older item will be deleted." and '
        '"Delete 1 item"', (tester) async {
      copies(11);
      await show(tester);
      await lowerLimitTo10(tester);
      expect(
        find.text(
          'Keep only the newest 10 items? 1 older item will be deleted.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Delete 1 item'), findsOne);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 1 item'));
      await tester.pumpAndSettle();
      expect(service.items.length, 10);
    });

    testWidgets('2 to delete: the plural, unchanged', (tester) async {
      copies(12);
      await show(tester);
      await lowerLimitTo10(tester);
      expect(
        find.text(
          'Keep only the newest 10 items? 2 older items will be deleted.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Delete 2 items'), findsOne);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('History: Clear history', () {
    Future<void> openClear(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
    }

    testWidgets('1 item: "This deletes the 1 item." (lead, 2026-11-06)', (
      tester,
    ) async {
      copies(1);
      await show(tester);
      await openClear(tester);
      expect(
        find.text('This deletes the 1 item. Snippets are not affected.'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('2 items: the plural, unchanged', (tester) async {
      copies(2);
      await show(tester);
      await openClear(tester);
      expect(
        find.text('This deletes all 2 items. Snippets are not affected.'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  });

  group('the lists\' screen-reader names', () {
    for (final n in [1, 2]) {
      final noun = n == 1 ? 'item' : 'items';

      testWidgets('History with $n: "Clipboard history, $n $noun"', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        copies(n);
        await show(tester);
        expect(
          find.bySemanticsLabel('Clipboard history, $n $noun'),
          findsOneWidget,
        );
        handle.dispose();
      });

      testWidgets('Snippets with $n: "Snippets, $n $noun", footer '
          '"$n ${n == 1 ? 'snippet' : 'snippets'}"', (tester) async {
        final handle = tester.ensureSemantics();
        for (var i = 1; i <= n; i++) {
          service.snippets.save(
            name: 'snip $i',
            content: 'content $i',
            type: SnippetType.other,
          );
        }
        await show(tester);
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'main-tab-snippets',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Snippets, $n $noun'), findsOneWidget);
        expect(
          find.text('$n ${n == 1 ? 'snippet' : 'snippets'}'),
          findsOneWidget,
        );
        handle.dispose();
      });
    }
  });

  group('BUG-W1: the Keep dialog follows the count while it is open', () {
    testWidgets('a copy arrives: "2 older items will be deleted." and '
        '"Delete 2 items", and confirming deletes those 2', (tester) async {
      copies(11);
      await show(tester);
      await lowerLimitTo10(tester);
      expect(find.widgetWithText(FilledButton, 'Delete 1 item'), findsOne);

      source.copy('arrived while the dialog was open');
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Keep only the newest 10 items? 2 older items will be deleted.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Delete 2 items'), findsOne);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 items'));
      await tester.pumpAndSettle();
      expect(service.items.length, 10);
      expect(service.limit, 10);
    });

    testWidgets('the count drops to 0 (an item deleted elsewhere): the '
        'dialog says 0, and confirming sets the limit and deletes nothing', (
      tester,
    ) async {
      copies(11);
      await show(tester);
      await lowerLimitTo10(tester);
      expect(find.widgetWithText(FilledButton, 'Delete 1 item'), findsOne);

      service.delete(service.items.last.id);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Keep only the newest 10 items? 0 older items will be deleted.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Delete 0 items'), findsOne);
      final before = [for (final i in service.items) i.id];
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 0 items'));
      await tester.pumpAndSettle();
      expect(service.limit, 10);
      expect([for (final i in service.items) i.id], before);
    });

    testWidgets('Cancel after the count changed keeps the old limit and '
        'every item', (tester) async {
      copies(11);
      await show(tester);
      await lowerLimitTo10(tester);
      source.copy('arrived while the dialog was open');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.limit, 200);
      expect(service.items.length, 12);
    });
  });
}
