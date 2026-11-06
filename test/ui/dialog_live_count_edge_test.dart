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

/// Tester round 12 on 2020e85 (BUG-W1 fix): the Clear history and Keep
/// dialogs follow the live count while open. What a click deletes must match
/// what the dialog says at that moment, singular and plural follow 1 <-> 2,
/// a count of 0 is safe, and no listener is left behind.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  void create({int limit = 200}) {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore()..setLimit(limit),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (_) async {},
    )..start();
  }

  setUp(create);
  tearDown(() => service.dispose());

  void copies(int n, [int from = 1]) {
    for (var i = from; i < from + n; i++) {
      source.copy('item $i');
    }
  }

  void snippets(int n, [int from = 1]) {
    for (var i = from; i < from + n; i++) {
      service.snippets.save(
        name: 'snip $i',
        content: 'content $i',
        type: SnippetType.other,
      );
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

  Future<void> lowerLimitTo(WidgetTester tester, int limit) async {
    final field = find.descendant(
      of: find.byType(LimitField),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '$limit');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> openClear(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
  }

  String noun(int n) => n == 1 ? 'item' : 'items';

  Finder keepText(int n, int removed) => find.text(
    'Keep only the newest $n items? '
    '$removed older ${noun(removed)} will be deleted.',
  );

  Finder clearText(int n) => find.text(
    n == 1
        ? 'This deletes the 1 item. Snippets are not affected.'
        : 'This deletes all $n items. Snippets are not affected.',
  );

  /// After [action], frames pass so the dialog rebuilds.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  int deleteButtonNumber(WidgetTester tester) {
    // The Keep dialog's Delete button (found by place, not by how its
    // label is built: W2 rebuilds the whole dialog from one count read).
    final button = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    final text = tester.widget<Text>(
      find.descendant(of: button, matching: find.byType(Text)),
    );
    return int.parse(
      RegExp(r'Delete (\d+) item').firstMatch(text.data!)!.group(1)!,
    );
  }

  // ------------------------------------------------------------ Clear history

  group('Clear history dialog follows the live count', () {
    testWidgets('1 -> 2 -> burst: the text, then Clear deletes exactly '
        'what it says', (tester) async {
      copies(1);
      await show(tester);
      await openClear(tester);
      expect(clearText(1), findsOneWidget);
      source.copy('two');
      await settle(tester);
      expect(clearText(2), findsOneWidget);
      expect(clearText(1), findsNothing);
      for (var i = 0; i < 3; i++) {
        source.copy('more $i');
        await settle(tester);
      }
      expect(clearText(5), findsOneWidget);
      copies(50, 100); // a burst in one frame
      await settle(tester);
      expect(clearText(55), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await settle(tester);
      expect(service.items, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('2 -> 1 -> 0 by deletes elsewhere: the text follows, the '
        'dialog stays open at 0, and Clear deletes nothing (no throw)', (
      tester,
    ) async {
      copies(3);
      snippets(2);
      await show(tester);
      await openClear(tester);
      service.delete(service.items.first.id);
      await settle(tester);
      expect(clearText(2), findsOneWidget);
      service.delete(service.items.first.id);
      await settle(tester);
      expect(clearText(1), findsOneWidget);
      service.delete(service.items.first.id);
      await settle(tester);
      expect(clearText(0), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'stays open');
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await settle(tester);
      expect(service.items, isEmpty);
      expect(service.snippets.items, hasLength(2), reason: 'snippets kept');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel after the count changed keeps everything that is '
        'there now', (tester) async {
      copies(2);
      await show(tester);
      await openClear(tester);
      copies(3, 10);
      await settle(tester);
      expect(clearText(5), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(service.items, hasLength(5));
    });

    testWidgets('the singular and the plural follow the count back and '
        'forth: 1, 2, 1, 2, 0, 1', (tester) async {
      copies(1);
      await show(tester);
      await openClear(tester);
      for (final step in [2, 1, 2, 0, 1]) {
        while (service.items.length < step) {
          source.copy('x${service.items.length}');
        }
        while (service.items.length > step) {
          service.delete(service.items.first.id);
        }
        await settle(tester);
        expect(clearText(step), findsOneWidget, reason: 'count $step');
        expect(find.textContaining('all 1 item'), findsNothing);
        expect(find.textContaining('the 2 item'), findsNothing);
      }
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });

    testWidgets('Clear with a copy arriving in the very frame of the click: '
        'everything is cleared (the service clears what is there)', (
      tester,
    ) async {
      copies(2);
      await show(tester);
      await openClear(tester);
      source.copy('late');
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await settle(tester);
      expect(service.items, isEmpty);
    });

    testWidgets('closed and reopened: the new count, not the old one', (
      tester,
    ) async {
      copies(1);
      await show(tester);
      await openClear(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      copies(4, 10);
      await openClear(tester);
      expect(clearText(5), findsOneWidget);
      source.copy('while open');
      await settle(tester);
      expect(clearText(6), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(service.items, hasLength(6));
    });

    testWidgets('nothing changes while it is open: Clear and Cancel both '
        'work as before', (tester) async {
      copies(3);
      await show(tester);
      await openClear(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(service.items, hasLength(3));
      await openClear(tester);
      expect(clearText(3), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await settle(tester);
      expect(service.items, isEmpty);
    });
  });

  // ----------------------------------------------------------------- Keep

  group('Keep dialog follows the live count', () {
    testWidgets('copies arriving: 5 -> 6 -> burst; the text, the button and '
        'its screen-reader label follow; Delete removes exactly the number '
        'the button says', (tester) async {
      final handle = tester.ensureSemantics();
      copies(15);
      await show(tester);
      await lowerLimitTo(tester, 10);
      expect(keepText(10, 5), findsOneWidget);
      source.copy('one more');
      await settle(tester);
      expect(keepText(10, 6), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Delete 6 items'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Delete 6 items'), findsOneWidget);
      copies(40, 100);
      await settle(tester);
      expect(keepText(10, 46), findsOneWidget);
      final before = service.items.length;
      final said = deleteButtonNumber(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 46 items'));
      await settle(tester);
      expect(before - service.items.length, said);
      expect(service.items.length, 10);
      expect(service.limit, 10);
      handle.dispose();
    });

    testWidgets('1 <-> 2 to delete: singular and plural in the text, the '
        'button and its screen-reader label, both ways', (tester) async {
      final handle = tester.ensureSemantics();
      copies(11);
      await show(tester);
      await lowerLimitTo(tester, 10);
      for (final removed in [1, 2, 1, 2, 1]) {
        while (service.items.length < 10 + removed) {
          source.copy('x${service.items.length}');
        }
        while (service.items.length > 10 + removed) {
          service.delete(service.items.first.id);
        }
        await settle(tester);
        expect(keepText(10, removed), findsOneWidget, reason: 'R=$removed');
        expect(
          find.widgetWithText(FilledButton, 'Delete $removed ${noun(removed)}'),
          findsOneWidget,
          reason: 'button, R=$removed',
        );
        expect(
          find.bySemanticsLabel('Delete $removed ${noun(removed)}'),
          findsOneWidget,
          reason: 'label, R=$removed',
        );
        expect(find.bySemanticsLabel('Delete 1 items'), findsNothing);
      }
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      handle.dispose();
    });

    testWidgets('the count drops to exactly the limit, then below it: the '
        'dialog stays open saying 0; confirming deletes nothing and still '
        'sets the limit', (tester) async {
      copies(13);
      await show(tester);
      await lowerLimitTo(tester, 10);
      expect(keepText(10, 3), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        service.delete(service.items.first.id);
      }
      await settle(tester);
      expect(keepText(10, 0), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Delete 0 items'),
        findsOneWidget,
      );
      for (var i = 0; i < 2; i++) {
        service.delete(service.items.first.id);
      }
      await settle(tester);
      expect(service.items, hasLength(8));
      expect(keepText(10, 0), findsOneWidget, reason: 'below the new limit');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 0 items'));
      await settle(tester);
      expect(service.items, hasLength(8), reason: 'nothing was deleted');
      expect(service.limit, 10, reason: 'the limit is still set');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel after the count dropped to 0 keeps the old limit and '
        'every item', (tester) async {
      copies(12);
      await show(tester);
      final oldLimit = service.limit;
      await lowerLimitTo(tester, 10);
      for (var i = 0; i < 5; i++) {
        service.delete(service.items.first.id);
      }
      await settle(tester);
      expect(keepText(10, 0), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(service.limit, oldLimit);
      expect(service.items, hasLength(7));
    });

    testWidgets('the count crosses the limit and back (15 -> 8 -> 15): the '
        'numbers follow each way', (tester) async {
      copies(15);
      await show(tester);
      await lowerLimitTo(tester, 10);
      expect(keepText(10, 5), findsOneWidget);
      for (var i = 0; i < 7; i++) {
        service.delete(service.items.first.id);
      }
      await settle(tester);
      expect(keepText(10, 0), findsOneWidget);
      copies(7, 200);
      await settle(tester);
      expect(keepText(10, 5), findsOneWidget);
      final before = service.items.length;
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 5 items'));
      await settle(tester);
      expect(before - service.items.length, 5);
    });

    testWidgets('Keep dialog: closed and reopened shows the live number', (
      tester,
    ) async {
      copies(12);
      await show(tester);
      await lowerLimitTo(tester, 10);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      copies(3, 50);
      await lowerLimitTo(tester, 10);
      expect(keepText(10, 5), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });

    testWidgets('nothing changes while open: Delete and Cancel work as '
        'before', (tester) async {
      copies(14);
      await show(tester);
      await lowerLimitTo(tester, 10);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(service.items, hasLength(14));
      await lowerLimitTo(tester, 10);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 4 items'));
      await settle(tester);
      expect(service.items, hasLength(10));
    });

    testWidgets('a copy arriving in the same frame as the click: the limit '
        'trims to the new limit, so what is deleted is what is over it', (
      tester,
    ) async {
      copies(12);
      await show(tester);
      await lowerLimitTo(tester, 10);
      source.copy('late');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 items'));
      await settle(tester);
      expect(service.items.length, 10);
      expect(service.limit, 10);
    });
  });

  // ------------------------------------ the screen left, no listener left

  group('lifecycle', () {
    testWidgets('the whole screen is removed while the Clear dialog is open: '
        'later changes do no setState on a disposed widget', (tester) async {
      copies(3);
      await show(tester);
      await openClear(tester);
      await tester.pumpWidget(const SizedBox());
      source.copy('after');
      service.delete(service.items.first.id);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // ignore: invalid_use_of_protected_member
      expect(service.hasListeners, isFalse, reason: 'a listener is left');
    });

    testWidgets('the same with the Keep dialog open', (tester) async {
      copies(13);
      await show(tester);
      await lowerLimitTo(tester, 10);
      await tester.pumpWidget(const SizedBox());
      source.copy('after');
      await tester.pump();
      expect(tester.takeException(), isNull);
      // ignore: invalid_use_of_protected_member
      expect(service.hasListeners, isFalse);
    });

    testWidgets('open and close both dialogs 15 times, with changes in '
        'between: no listener survives the screen', (tester) async {
      copies(12);
      await show(tester);
      for (var i = 0; i < 15; i++) {
        await openClear(tester);
        source.copy('c$i');
        await settle(tester);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        await lowerLimitTo(tester, 10);
        service.delete(service.items.last.id);
        await settle(tester);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'round $i');
      }
      await tester.pumpWidget(const SizedBox());
      // ignore: invalid_use_of_protected_member
      expect(service.hasListeners, isFalse, reason: 'a listener leaked');
    });

    testWidgets('changes after both dialogs are closed cause no exception '
        'and the list still follows the count', (tester) async {
      final handle = tester.ensureSemantics();
      copies(2);
      await show(tester);
      await openClear(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      for (var i = 0; i < 5; i++) {
        source.copy('x$i');
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('Clipboard history, 7 items'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('BUG-F1 (pre-existing, found here): the History footer '
        '"N of 200 items" keeps following the count: after copies 5 s '
        'apart it freezes after the second update, even with no dialog', (
      tester,
    ) async {
      // Cause (developer, BUG-F1): setUp starts the service OUTSIDE this
      // test's fake-async zone, so the fake clipboard's stream calls the
      // screen's listener in the real zone, and the footer's 2-second
      // throttle timer armed there runs on real time: tester.pump never
      // fires it, and the footer waits for ever. In the app everything
      // runs in one zone and the footer follows. The service is made here,
      // inside the test, so its timers run on the test's clock.
      service.dispose();
      create();
      copies(2);
      await show(tester);
      for (var i = 0; i < 6; i++) {
        source.copy('x$i');
        await tester.pump(const Duration(seconds: 5));
      }
      expect(
        find.text('8 of 200 items'),
        findsOneWidget,
        reason: 'the footer is stale with ${service.items.length} items',
      );
    });
  });
}
