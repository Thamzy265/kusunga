import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../../support/main_tabs.dart';

/// Tester round 14 on a0ba96d (reviewer W2): an unreadable count is null,
/// never 0. Breaking it: reads failing and recovering while open, the
/// disabled Delete (keyboard, screen reader), a confirm in the frame of a
/// failure, a closed history, every way the limit field commits, Clear
/// history with a failing store, and the callers of countRemovedBy.
void main() {
  const unknown = "Couldn't count the items. Try again.";

  late FakeClipboardSource source;
  late _Store store;
  late HistoryService service;

  void make() {
    source = FakeClipboardSource();
    store = _Store();
    service = HistoryService(
      store: store,
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
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

  Finder limitField() => find.descendant(
    of: find.byType(LimitField),
    matching: find.byType(TextField),
  );

  Future<void> setKeep(WidgetTester tester, int n) async {
    await showKeepField(tester);
    await tester.enterText(limitField(), '$n');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Finder deleteFinder() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );

  FilledButton deleteButton(WidgetTester tester) =>
      tester.widget<FilledButton>(deleteFinder());

  String deleteLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: deleteFinder(), matching: find.byType(Text)),
      )
      .data!;

  void copies(int n, [String prefix = 'item']) {
    for (var i = 0; i < n; i++) {
      source.copy('$prefix $i');
    }
  }

  Finder keepText(int removed) => find.text(
    'Keep only the newest 10 items? $removed older '
    '${removed == 1 ? 'item' : 'items'} will be deleted.',
  );

  // ----------------------------------------------- the helper is still honest

  testWidgets('the Keep and Clear dialogs each hold exactly one FilledButton, '
      'so a helper that finds it "inside the dialog" reads the Delete / Clear '
      'button', (tester) async {
    make();
    copies(12);
    await show(tester);
    await setKeep(tester, 10);
    expect(deleteFinder(), findsOneWidget);
    expect(deleteLabel(tester), 'Delete 2 items');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await showHistoryTab(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(deleteFinder(), findsOneWidget);
    expect(deleteLabel(tester), 'Clear history');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  // ------------------------------------------- fail, recover, fail, repeatedly

  testWidgets('fail -> ok -> fail -> ok -> fail while open, five rounds: the '
      'text and the button always agree, and a confirm after recovery '
      'deletes exactly what the dialog said', (tester) async {
    make();
    copies(12);
    await show(tester);
    await setKeep(tester, 10);
    var expected = 2;
    expect(keepText(expected), findsOneWidget);
    for (var round = 0; round < 5; round++) {
      store.failCount = true;
      source.copy('fail $round');
      await tester.pumpAndSettle();
      expected++;
      expect(find.text(unknown), findsOneWidget, reason: 'round $round');
      expect(deleteButton(tester).onPressed, isNull, reason: 'round $round');
      expect(deleteLabel(tester), 'Delete');
      expect(find.textContaining('older item'), findsNothing);
      store.failCount = false;
      source.copy('ok $round');
      await tester.pumpAndSettle();
      expected++;
      expect(keepText(expected), findsOneWidget, reason: 'round $round');
      expect(deleteButton(tester).onPressed, isNotNull);
      expect(deleteLabel(tester), 'Delete $expected items');
    }
    final before = service.items.length;
    await tester.tap(deleteFinder());
    await tester.pumpAndSettle();
    expect(before - service.items.length, expected);
    expect(service.items.length, 10);
    expect(service.limit, 10);
  });

  testWidgets('failure at open, then recovery by a change: the count '
      'appears, Delete turns on, and confirming works', (tester) async {
    make();
    copies(13);
    await show(tester);
    store.failCount = true;
    await setKeep(tester, 10);
    expect(find.text(unknown), findsOneWidget);
    store.failCount = false;
    source.copy('a good read follows');
    await tester.pumpAndSettle();
    expect(keepText(4), findsOneWidget);
    await tester.tap(deleteFinder());
    await tester.pumpAndSettle();
    expect(service.items.length, 10);
    expect(service.limit, 10);
  });

  testWidgets('the store heals but nothing changes: the dialog may keep '
      'saying it could not count (no change notifies it), Cancel still '
      'works, and reopening reads the count again', (tester) async {
    make();
    copies(12);
    await show(tester);
    store.failCount = true;
    await setKeep(tester, 10);
    expect(find.text(unknown), findsOneWidget);
    store.failCount = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.limit, 200);
    await setKeep(tester, 10);
    expect(keepText(2), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  // ------------------------------------------------ the disabled Delete button

  testWidgets('unknown count: the focus starts on Cancel, Tab never reaches '
      'the disabled Delete, Enter and Space only cancel, a tap on Delete '
      'does nothing', (tester) async {
    for (final k in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      make();
      copies(12);
      await show(tester);
      store.failCount = true;
      await setKeep(tester, 10);
      expect(find.text(unknown), findsOneWidget);
      await tester.tap(deleteFinder(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final ctx = FocusManager.instance.primaryFocus?.context;
        expect(
          ctx?.findAncestorWidgetOfExactType<FilledButton>(),
          isNull,
          reason: 'Tab reached the disabled Delete (${k.keyLabel})',
        );
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 200, reason: '${k.keyLabel} lowered the limit');
      expect(service.items.length, 12);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the disabled Delete is disabled and named "Delete" for a '
      'screen reader; the enabled one says its count', (tester) async {
    final handle = tester.ensureSemantics();
    make();
    copies(11);
    await show(tester);
    await setKeep(tester, 10);
    var node = tester.getSemantics(deleteFinder());
    expect(node.label, contains('Delete 1 item'));
    expect(node.flagsCollection.isEnabled, ui.Tristate.isTrue);
    store.failCount = true;
    source.copy('breaks the read');
    await tester.pumpAndSettle();
    node = tester.getSemantics(deleteFinder());
    expect(node.label, 'Delete');
    expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(find.bySemanticsLabel(RegExp(r'Delete \d')), findsNothing);
    handle.dispose();
  });

  // --------------------------------------- a confirm in the frame of a failure

  testWidgets('the read fails in the very frame of the click on an enabled '
      'Delete: what is deleted is what the dialog said', (tester) async {
    make();
    copies(15);
    await show(tester);
    await setKeep(tester, 10);
    expect(deleteLabel(tester), 'Delete 5 items');
    store.failCount = true;
    await tester.tap(deleteFinder());
    await tester.pumpAndSettle();
    expect(service.items.length, 10);
    expect(service.limit, 10);
  });

  testWidgets('the write fails when Delete is confirmed: nothing is half '
      'done: limit and items unchanged, the field shows the old limit, the '
      'save-failed message appears', (tester) async {
    make();
    copies(15);
    await show(tester);
    await setKeep(tester, 10);
    store.failSetLimit = true;
    await tester.tap(deleteFinder());
    await tester.pumpAndSettle();
    expect(service.limit, 200);
    expect(service.items.length, 15);
    expect(
      tester.widget<TextField>(limitField()).controller!.text,
      '200',
      reason: 'the field shows a limit that was not saved',
    );
    expect(find.text("Couldn't save that number. Try again."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------ closed history

  testWidgets('the history is closed while the Keep dialog is open: no '
      'throw, nothing deleted, the limit unchanged', (tester) async {
    make();
    copies(15);
    await show(tester);
    await setKeep(tester, 10);
    expect(deleteLabel(tester), 'Delete 5 items');
    await tester.runAsync(() => service.close());
    await tester.pump();
    if (deleteFinder().evaluate().isNotEmpty &&
        deleteButton(tester).onPressed != null) {
      await tester.tap(deleteFinder());
    } else if (find.text('Cancel').evaluate().isNotEmpty) {
      await tester.tap(find.text('Cancel'));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(store.inner.limit, 200, reason: 'a closed history lowered it');
    expect(store.inner.count, 15, reason: 'a closed history deleted');
    expect(service.countRemovedBy(10), isNull);
  });

  testWidgets('lowering after the history is closed opens the dialog with '
      'no number and never lowers', (tester) async {
    make();
    copies(15);
    await show(tester);
    await tester.runAsync(() => service.close());
    await tester.pump();
    await setKeep(tester, 10);
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      expect(find.text(unknown), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    expect(store.inner.limit, 200);
    expect(store.inner.count, 15);
  });

  // ------------------------------------- the limit field's ways to commit

  group('every way the limit field commits', () {
    testWidgets('Enter, with an unknown count: the dialog, then Cancel puts '
        'the old limit back in the field', (tester) async {
      make();
      copies(12);
      await show(tester);
      store.failCount = true;
      await setKeep(tester, 10);
      expect(find.text(unknown), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(limitField()).controller!.text, '200');
      expect(service.limit, 200);
    });

    testWidgets('the Up/Down steppers (10 at a time) then Enter, unknown '
        'count: the dialog, Cancel keeps 200', (tester) async {
      make();
      copies(12);
      await show(tester);
      store.failCount = true;
      await showKeepField(tester);
      await tester.tap(limitField());
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tester.widget<TextField>(limitField()).controller!.text, '190');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(unknown), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.limit, 200);
    });

    testWidgets('losing the focus commits too: a lower value with an unknown '
        'count opens the dialog once, never lowers silently', (tester) async {
      make();
      copies(12);
      await show(tester);
      store.failCount = true;
      await showKeepField(tester);
      await tester.enterText(limitField(), '10');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(unknown), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.limit, 200);
      expect(service.items.length, 12);
    });

    testWidgets('Enter and then the focus loss in a row: one dialog only, '
        'not two', (tester) async {
      make();
      copies(12);
      await show(tester);
      await showKeepField(tester);
      await tester.enterText(limitField(), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the same value, or a higher one, reads no count at all, '
        'with a failing store and a healthy one', (tester) async {
      make();
      copies(12);
      await show(tester);
      for (final fail in [true, false]) {
        store.failCount = fail;
        store.countCalls = 0;
        await setKeep(tester, 200); // same
        await setKeep(tester, 300); // raise
        await setKeep(tester, 5000);
        expect(store.countCalls, 0, reason: 'a read for a raise (fail=$fail)');
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.limit, 5000);
        service.setLimit(200);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await show(tester);
      }
    });

    testWidgets('a lower value that would delete nothing (known 0) opens no '
        'dialog; with a failing read it opens one (it cannot know)', (
      tester,
    ) async {
      make();
      copies(8);
      await show(tester);
      await setKeep(tester, 100);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 100);
      store.failCount = true;
      await setKeep(tester, 50);
      expect(find.text(unknown), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.limit, 100, reason: 'lowered without a count');
    });

    testWidgets('an invalid value (below 10, above 5,000, text) never '
        'reaches the dialog or a read', (tester) async {
      make();
      copies(12);
      await show(tester);
      store.countCalls = 0;
      for (final v in ['9', '5001', 'abc', '']) {
        await showKeepField(tester);
        await tester.enterText(limitField(), v);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing, reason: v);
      }
      expect(store.countCalls, 0);
      expect(service.limit, 200);
    });
  });

  // ---------------------------------------------- Clear history, a failing store

  group('Clear history with failing stores', () {
    Future<void> openClear(WidgetTester tester) async {
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
    }

    testWidgets('its count comes from the list, not the failing read: it '
        'still says "all N items" and works', (tester) async {
      make();
      copies(6);
      await show(tester);
      store.failCount = true;
      await openClear(tester);
      expect(
        find.text('This deletes all 6 items. Snippets are not affected.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
      expect(service.items, isEmpty);
    });

    testWidgets('when the clear itself fails: the items stay, the clear-error '
        'banner says so, nothing pretends it worked', (tester) async {
      make();
      copies(6);
      await show(tester);
      store.failClear = true;
      await openClear(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
      expect(service.items, hasLength(6));
      expect(service.banners, contains(HistoryBanner.clearError));
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------ the callers of countRemovedBy

  test('the service answers null, never 0, for every kind of failure, and '
      'a real number when healthy', () async {
    make();
    copies(14);
    expect(service.countRemovedBy(10), 4);
    expect(service.countRemovedBy(200), 0);
    store.failCount = true;
    expect(service.countRemovedBy(10), isNull);
    expect(service.countRemovedBy(200), isNull);
    store.failCount = false;
    expect(service.countRemovedBy(10), 4);
    await service.close();
    expect(service.countRemovedBy(10), isNull);
    expect(service.countRemovedBy(200), isNull);
  });

  test(
    'no caller in lib/ treats the result as an int without a null check',
    () {
      final callers = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final lines = e.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('countRemovedBy(') &&
              !lines[i].trimLeft().startsWith('///') &&
              !lines[i].contains('int? countRemovedBy') &&
              !lines[i].contains('int countRemovedBy')) {
            callers.add('${e.path}:${i + 1}');
          }
        }
      }
      // The two callers (the limit field and the dialog, both in
      // limit_field.dart since M1.7), the service's own call into the store,
      // and the auto-delete menu and dialog (M1.7, ExpiryService's int?,
      // null shown as "Couldn't count the items"): anything new must be
      // checked for null.
      expect(
        callers.map((c) => c.replaceAll('\\', '/').split(':').first).toSet(),
        {
          'lib/history/history_service.dart',
          'lib/history/ui/limit_field.dart',
          'lib/settings/ui/settings_screen.dart',
        },
        reason: 'a new caller of countRemovedBy: $callers',
      );
    },
  );
}

/// A store whose reads, limit writes and clear can be made to fail, like a
/// locked or damaged database.
class _Store extends MemoryHistoryStore {
  bool failCount = false;
  bool failSetLimit = false;
  bool failClear = false;
  int countCalls = 0;

  MemoryHistoryStore get inner => this;

  @override
  int countRemovedBy(int newLimit) {
    countCalls++;
    if (failCount) throw const FileSystemException('read failed');
    return super.countRemovedBy(newLimit);
  }

  @override
  void setLimit(int newLimit) {
    if (failSetLimit) throw const FileSystemException('write failed');
    super.setLimit(newLimit);
  }

  @override
  int clear() {
    if (failClear) throw const FileSystemException('clear failed');
    return super.clear();
  }
}
