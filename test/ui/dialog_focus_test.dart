import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

/// BUG-D1: the History list must never take the focus while a route is on
/// top of it. The first row asks for the focus (autofocus) every time a row
/// becomes the first one, and Flutter grants that whenever the list's own
/// scope has no focused child, whichever route holds the focus. Enter in the
/// limit field leaves the scope without one (the field unfocuses itself), so
/// a copy, or a delete of the first item, pulled the focus out of the open
/// dialog: Escape and Enter then did nothing, and Tab walked the rows behind
/// it. The Clear history dialog has the same hole after an Enter in the field.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  late _Store store;

  void create({int limit = 200}) {
    source = FakeClipboardSource();
    service = HistoryService(
      store: store = (_Store()..setLimit(limit)),
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

  Finder field() => find.descendant(
    of: find.byType(LimitField),
    matching: find.byType(TextField),
  );

  /// Types [limit] into the field and presses Enter, as the user does.
  Future<void> enterLimit(WidgetTester tester, int limit) async {
    await tester.enterText(field(), '$limit');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> openClear(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> shiftTab(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
  }

  /// The label of the dialog button that has the focus, or where the focus
  /// is instead.
  String focused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return 'nothing';
    if (ctx.findAncestorWidgetOfExactType<AlertDialog>() == null) {
      final row = ctx.findAncestorWidgetOfExactType<HistoryRow>();
      return row != null ? 'row ${row.item.id}' : 'outside the dialog';
    }
    final text = ctx.findAncestorWidgetOfExactType<TextButton>();
    final filled = ctx.findAncestorWidgetOfExactType<FilledButton>();
    if (text != null) return (text.child as Text).data!;
    if (filled != null) return (filled.child as Text).data!;
    return 'the dialog';
  }

  Finder deleteFinder() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );
  String deleteLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: deleteFinder(), matching: find.byType(Text)),
      )
      .data!;

  /// Tab, Tab, Shift+Tab: every stop is Cancel or the Delete button.
  Future<void> expectTabStaysInside(WidgetTester tester, String step) async {
    final inside = {'Cancel', deleteLabel(tester)};
    await key(tester, LogicalKeyboardKey.tab);
    expect(inside, contains(focused()), reason: '$step: Tab');
    await key(tester, LogicalKeyboardKey.tab);
    expect(inside, contains(focused()), reason: '$step: Tab, Tab');
    await shiftTab(tester);
    expect(inside, contains(focused()), reason: '$step: Shift+Tab');
  }

  group('the Keep dialog opened by Enter in the field', () {
    testWidgets('keeps the focus inside through a copy, deletes of the first '
        'item, 0, unknown and back: Tab and Shift+Tab stop only at Cancel '
        'and the Delete button, and Escape closes it', (tester) async {
      copies(12);
      await show(tester);
      await enterLimit(tester, 10);
      expect(deleteLabel(tester), 'Delete 2 items');
      expect(focused(), 'Cancel');

      final steps = <(String, void Function())>[
        ('a copy', () => source.copy('arrives while open')),
        (
          'the first item deleted',
          () => service.delete(service.items.first.id),
        ),
        (
          'the first item deleted',
          () => service.delete(service.items.first.id),
        ),
        (
          'the first item deleted',
          () => service.delete(service.items.first.id),
        ),
        ('down to 0', () => service.delete(service.items.first.id)),
        (
          'unknown',
          () {
            store.failCount = true;
            service.setLimit(service.limit);
          },
        ),
        (
          'known again',
          () {
            store.failCount = false;
            service.setLimit(service.limit);
          },
        ),
        ('a copy at 0', () => source.copy('one over')),
      ];
      for (final (step, change) in steps) {
        change();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget, reason: step);
        expect(
          focused(),
          anyOf('Cancel', deleteLabel(tester), 'the dialog'),
          reason: '$step: the focus left the dialog',
        );
        await expectTabStaysInside(tester, step);
      }

      // Whatever Tab reached, Escape closes it and nothing behind it changed.
      final before = service.items.length;
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.tab);
      }
      expect(focused(), anyOf('Cancel', deleteLabel(tester)));
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing, reason: 'Escape');
      expect(service.items.length, before);
      expect(service.limit, 200);
    });

    testWidgets('the focus on "Delete N items" when the count turns unknown '
        'lands on Cancel, stays there when it is known again, and Tab then '
        'reaches the Delete button again', (tester) async {
      copies(12);
      await show(tester);
      await enterLimit(tester, 10);
      await key(tester, LogicalKeyboardKey.tab);
      expect(focused(), 'Delete 2 items');

      store.failCount = true;
      service.setLimit(service.limit);
      await tester.pumpAndSettle();
      expect(deleteLabel(tester), 'Delete');
      expect(focused(), 'Cancel', reason: 'a disabled button cannot keep it');

      store.failCount = false;
      service.setLimit(service.limit);
      await tester.pumpAndSettle();
      expect(deleteLabel(tester), 'Delete 2 items');
      expect(focused(), 'Cancel', reason: 'it does not jump back on its own');

      await key(tester, LogicalKeyboardKey.tab);
      expect(focused(), 'Delete 2 items');
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 10);
      expect(service.items, hasLength(10));
    });

    testWidgets('the focus on "Delete N items" stays on that button when it '
        'turns into "Set limit"; Enter then sets the limit and deletes '
        'nothing', (tester) async {
      copies(11);
      await show(tester);
      await enterLimit(tester, 10);
      await key(tester, LogicalKeyboardKey.tab);
      expect(focused(), 'Delete 1 item');

      service.delete(service.items.first.id);
      await tester.pumpAndSettle();
      expect(focused(), 'Set limit');

      await key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 10);
      expect(service.items, hasLength(10));
    });

    testWidgets('after Cancel with a copy arrived meanwhile: the newest row '
        'takes the focus, as a copy does with no dialog open while nothing on '
        'the screen has it', (tester) async {
      copies(12);
      await show(tester);
      await enterLimit(tester, 10);
      source.copy('arrives while open');
      await tester.pumpAndSettle();
      expect(focused(), 'Cancel');
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'row ${service.items.first.id}');
      expect(service.limit, 200);
    });
  });

  group('the Clear history dialog', () {
    testWidgets('opened after an Enter in the limit field (the same value, '
        'so no Keep dialog): a copy arrives, the focus stays inside, Escape '
        'closes it and nothing behind it is touched', (tester) async {
      copies(4);
      await show(tester);
      await enterLimit(tester, 200);
      expect(find.byType(AlertDialog), findsNothing);
      await openClear(tester);
      expect(focused(), 'Cancel');

      source.copy('arrives while open');
      await tester.pumpAndSettle();
      expect(focused(), 'Cancel', reason: 'the focus left the dialog');
      final before = service.items.length;
      await expectTabStaysInside(tester, 'after the copy');
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.tab);
      }
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing, reason: 'Escape');
      expect(service.items.length, before);
    });
  });
}

class _Store extends MemoryHistoryStore {
  bool failCount = false;

  @override
  int countRemovedBy(int newLimit) {
    if (failCount) throw const FileSystemException('read failed');
    return super.countRemovedBy(newLimit);
  }
}
