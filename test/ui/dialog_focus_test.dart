import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';
import '../support/main_tabs.dart';

/// BUG-D1: the History list must never take the focus while a route is on
/// top of it. The first row asks for the focus (autofocus) every time a row
/// becomes the first one, and Flutter grants that whenever the list's own
/// scope has no focused child, whichever route holds the focus. Enter in the
/// limit field leaves the scope without one (the field unfocuses itself), so
/// a copy, or a delete of the first item, pulled the focus out of the open
/// dialog: Escape and Enter then did nothing, and Tab walked the rows behind
/// it. The Clear history dialog has the same hole after an Enter in the field.
///
/// The same rule (nothing behind a route on top may take the focus) covers
/// the Mac setup card heading (BUG-D4) and a scroll-and-focus request still
/// on its way (BUG-D3). And when a dialog closes the focus goes back to the
/// control that opened it (BUG-D2, spec line 72): the Keep field, or the
/// More options button.
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
    await showKeepField(tester);
    await tester.enterText(field(), '$limit');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> openClear(WidgetTester tester) async {
    await showHistoryTab(tester);
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
      if (row != null) return 'row ${row.item.id}';
      if (ctx.findAncestorWidgetOfExactType<TextField>() != null) {
        return 'field';
      }
      if (ctx.findAncestorWidgetOfExactType<PopupMenuButton<Object?>>() !=
          null) {
        return 'more-button';
      }
      if (find
          .descendant(
            of: find.byWidget(ctx.widget),
            matching: find.text('Allow Kusunga to read what you copy'),
          )
          .evaluate()
          .isNotEmpty) {
        return 'setup-card';
      }
      return 'outside the dialog (${ctx.widget.runtimeType})';
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
  });

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(field()).controller!.text;

  group('after the Keep dialog closes the focus is back in the Keep field '
      '(BUG-D2, spec line 72)', () {
    for (final how in ['Cancel by mouse', 'Escape', 'confirm by mouse']) {
      for (final copyBetween in [false, true]) {
        testWidgets('$how${copyBetween ? ', a copy meanwhile' : ''}: the '
            'field has the focus and shows the limit; the newest row does not '
            'take it, nor does a later copy', (tester) async {
          copies(12);
          await show(tester);
          await enterLimit(tester, 10);
          expect(focused(), 'Cancel');
          if (copyBetween) {
            source.copy('between');
            await tester.pumpAndSettle();
          }
          switch (how) {
            case 'Cancel by mouse':
              await tester.tap(find.text('Cancel'));
            case 'Escape':
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            default:
              await tester.tap(deleteFinder());
          }
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(focused(), 'field', reason: how);
          final confirmed = how == 'confirm by mouse';
          expect(service.limit, confirmed ? 10 : 200);
          expect(fieldText(tester), confirmed ? '10' : '200');
          source.copy('later');
          await tester.pumpAndSettle();
          expect(focused(), 'field', reason: 'a later copy moved it');
        });
      }
    }

    testWidgets('keyboard only: Enter on Cancel, then again with Tab and '
        'Enter on the Delete button: the field has the focus both times', (
      tester,
    ) async {
      copies(12);
      await show(tester);
      await enterLimit(tester, 10);
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'field');
      expect(service.limit, 200);
      await enterLimit(tester, 10);
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'field');
      expect(service.limit, 10);
      expect(fieldText(tester), '10');
    });

    testWidgets('opened by Tab out of the field (the commit on losing the '
        'focus): after Escape the field has the focus again', (tester) async {
      copies(12);
      await show(tester);
      await showKeepField(tester);
      await tester.enterText(field(), '10');
      await key(tester, LogicalKeyboardKey.tab);
      expect(find.byType(AlertDialog), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'field');
      expect(service.limit, 200);
    });

    testWidgets('the Mac setup card appears while the dialog is open: the '
        'dialog keeps the focus, and after Escape the field has it, not the '
        'card heading (BUG-D4)', (tester) async {
      copies(12);
      await show(tester);
      await enterLimit(tester, 10);
      source.access = PasteAccess.needsSetup;
      await tester.runAsync(() => service.recheckPasteAccess());
      await tester.pumpAndSettle();
      // The card is in the History tab, behind Settings and the dialog.
      expect(
        find.text('Allow Kusunga to read what you copy', skipOffstage: false),
        findsOneWidget,
      );
      expect(focused(), 'Cancel');
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'field');
    });
  });

  group('after the Clear history dialog closes the focus is on the More '
      'options button (BUG-D2, spec line 72)', () {
    for (final how in [
      'Cancel by mouse',
      'Escape',
      'confirm by mouse',
      'auto-close at 0',
    ]) {
      for (final copyBetween in [false, true]) {
        testWidgets('opened by mouse after an Enter in the field, '
            '$how${copyBetween ? ', a copy meanwhile' : ''}', (tester) async {
          copies(4);
          await show(tester);
          await enterLimit(tester, 200);
          await openClear(tester);
          expect(focused(), 'Cancel');
          if (copyBetween) {
            source.copy('between');
            await tester.pumpAndSettle();
          }
          switch (how) {
            case 'Cancel by mouse':
              await tester.tap(find.text('Cancel'));
            case 'Escape':
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            case 'confirm by mouse':
              await tester.tap(deleteFinder());
            default:
              service.clear();
          }
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(focused(), 'more-button', reason: how);
          source.copy('later');
          await tester.pumpAndSettle();
          expect(focused(), 'more-button', reason: 'a later copy moved it');
        });
      }
    }

    testWidgets('opened by keyboard (Shift+Tab to More options, Enter, Down, '
        'Enter), a copy, Escape: the More options button has the focus', (
      tester,
    ) async {
      copies(4);
      await show(tester);
      for (var i = 0; i < 40 && focused() != 'more-button'; i++) {
        await shiftTab(tester);
      }
      expect(focused(), 'more-button');
      await key(tester, LogicalKeyboardKey.enter);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.text('Clear all history?'), findsOneWidget);
      source.copy('between');
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'more-button');
      expect(service.items, hasLength(5));
    });

    testWidgets('the focus returns to the very node Tab reaches for the '
        'visible More options button, not a node above or beside it: after '
        'the dialog and after the menu (reviewer F-M1)', (tester) async {
      copies(4);
      await show(tester);
      for (var i = 0; i < 40 && focused() != 'more-button'; i++) {
        await shiftTab(tester);
      }
      final byTab = FocusManager.instance.primaryFocus!;
      final button = byTab.context!.findAncestorWidgetOfExactType<IconButton>();
      expect(button?.tooltip, 'More options', reason: 'Tab is on the button');
      // Nothing focused on the screen, then the dialog by mouse.
      await enterLimit(tester, 200);
      expect(FocusManager.instance.primaryFocus, isNot(same(byTab)));
      await openClear(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(byTab), reason: 'dialog');
      expect(byTab.hasPrimaryFocus, isTrue);
      await enterLimit(tester, 200);
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(FocusManager.instance.primaryFocus, same(byTab), reason: 'menu');
    });

    testWidgets('the menu itself, opened by mouse and dismissed with Escape '
        'or a click outside: the More options button has the focus', (
      tester,
    ) async {
      copies(4);
      await show(tester);
      await enterLimit(tester, 200);
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Clear history'), findsNothing);
      expect(focused(), 'more-button', reason: 'Escape');
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 600));
      await tester.pumpAndSettle();
      expect(find.text('Clear history'), findsNothing);
      expect(focused(), 'more-button', reason: 'a click outside');
    });
  });

  group('a scroll-and-focus request still on its way when a route goes on '
      'top is dropped (BUG-D3)', () {
    testWidgets('End in a 400-row list, the More menu opened in the same '
        'frame: no row takes the focus from the menu, nor later from the '
        'Clear dialog; after Escape the More button has it and the request '
        'is not resumed', (tester) async {
      service.dispose();
      create(limit: 5000);
      copies(400);
      await show(tester);
      await tester.tap(find.byType(HistoryRow).first, warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      (tester.state(find.byType(PopupMenuButton<Object?>))
              as PopupMenuButtonState<Object?>)
          .showButtonMenu();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(focused(), isNot(startsWith('row')), reason: 'frame $i');
      }
      expect(find.text('Clear history'), findsOneWidget);
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(focused(), 'Cancel');
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(focused(), 'more-button');
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(focused(), 'more-button', reason: 'the End request resumed');
      expect(service.items, hasLength(400));
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
