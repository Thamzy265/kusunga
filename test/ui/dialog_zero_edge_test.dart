import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';
import '../support/main_tabs.dart';

/// Tester round 15 on be09a77 (PM decision 2026-11-08 "Close or relabel"): the
/// Clear history dialog closes itself at a count of 0; the Keep dialog says
/// "No items will be deleted." with a "Set limit" button. Breaking it: bursts,
/// same-frame copies, Escape/Enter around the close, dialogs on top, the
/// screen removed, listeners, focus, 0 <-> 1 <-> unknown, and the field.
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

  Future<void> show(WidgetTester tester, {bool animate = false}) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: !animate),
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
    await showKeepField(tester);
    await tester.enterText(field, '$limit');
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

  String noun(int n) => n == 1 ? 'item' : 'items';

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  Finder clearText(int n) => find.text(
    n == 1
        ? 'This deletes the 1 item. Snippets are not affected.'
        : 'This deletes all $n items. Snippets are not affected.',
  );
  Finder keepText(int removed) => find.text(
    'Keep only the newest 10 items? $removed older ${noun(removed)} will be '
    'deleted.',
  );
  Finder keepZero() =>
      find.text('Keep only the newest 10 items? No items will be deleted.');
  const unknown = "Couldn't count the items. Try again.";

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

  Future<void> frames(WidgetTester tester, int n, List<String> sink) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final t = w.data;
        if (t != null && t.contains('all 0 items')) sink.add('frame $i: $t');
      }
    }
  }

  String? focusSignature() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    final w = ctx.widget;
    final tooltip = ctx
        .findAncestorWidgetOfExactType<PopupMenuButton<Object?>>()
        ?.tooltip;
    return '${w.runtimeType}|$tooltip|${ctx.findAncestorWidgetOfExactType<TextField>() != null}';
  }

  // ------------------------------------------------ Clear history reaching 0

  group('Clear history at a count of 0', () {
    testWidgets('a burst: 60 items deleted one after the other: closes once, '
        'no frame ever shows "all 0 items", no exception', (tester) async {
      copies(60);
      await show(tester);
      await openClear(tester);
      final seen = <String>[];
      for (final item in List.of(service.items)) {
        service.delete(item.id);
        await frames(tester, 1, seen);
      }
      await frames(tester, 20, seen);
      expect(find.byType(AlertDialog), findsNothing);
      expect(seen, isEmpty, reason: 'a "0" frame: $seen');
      expect(tester.takeException(), isNull);
      expect(service.items, isEmpty);
    });

    testWidgets('by a Clear from another path while the dialog is open: it '
        'closes like Cancel, and nothing runs twice', (tester) async {
      copies(5);
      await show(tester);
      await openClear(tester);
      final removed = service.clear();
      expect(removed, 5);
      final seen = <String>[];
      await frames(tester, 20, seen);
      expect(find.byType(AlertDialog), findsNothing);
      expect(seen, isEmpty);
      expect(tester.takeException(), isNull);
      expect(service.banners, isNot(contains(HistoryBanner.clearError)));
    });

    testWidgets('the count hits 0 and a copy lands in the same frame (both '
        'orders): the dialog closes, one item is kept, nothing throws', (
      tester,
    ) async {
      for (final copyFirst in [false, true]) {
        service.dispose();
        create();
        copies(3);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        await openClear(tester);
        if (copyFirst) source.copy('landed');
        service.clear();
        if (!copyFirst) source.copy('landed');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'copyFirst=$copyFirst');
        if (copyFirst) {
          // The clear removed everything including the new copy: closed.
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsNothing);
          expect(service.items, hasLength(1));
        }
      }
    });

    testWidgets('Escape in the same frame as the auto-close (animations on): '
        'no double pop, no exception', (tester) async {
      copies(2);
      await show(tester, animate: true);
      await openClear(tester);
      service.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.banners, isNot(contains(HistoryBanner.clearError)));
    });

    testWidgets('Escape while the exit animation already runs, then the '
        'count hits 0: no throw (the route is already leaving)', (
      tester,
    ) async {
      copies(2);
      await show(tester, animate: true);
      await openClear(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 50));
      service.clear();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Enter on Cancel (the default focus) in the frame of the '
        'auto-close: nothing is confirmed twice, no exception', (tester) async {
      copies(2);
      await show(tester, animate: true);
      await openClear(tester);
      service.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.banners, isNot(contains(HistoryBanner.clearError)));
    });

    testWidgets('focus on "Clear history" (Tab) and Enter in the frame of the '
        'auto-close: harmless, an empty list stays empty, no exception', (
      tester,
    ) async {
      copies(2);
      await show(tester, animate: true);
      await openClear(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      service.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.items, isEmpty);
    });

    testWidgets('a second dialog on top of Clear when it hits 0: Clear is '
        'removed, the one on top stays and works, nothing is cleared twice', (
      tester,
    ) async {
      copies(3);
      await show(tester);
      await openClear(tester);
      final ctx = tester.element(find.byType(AlertDialog));
      var closedTop = false;
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: const Text('On top'),
            actions: [
              TextButton(
                onPressed: () {
                  closedTop = true;
                  Navigator.of(c).pop();
                },
                child: const Text('Close top'),
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(find.text('On top'), findsOneWidget);
      service.clear();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('On top'), findsOneWidget, reason: 'the top one stays');
      expect(find.text('Clear all history?'), findsNothing);
      await tester.tap(find.text('Close top'));
      await settle(tester);
      expect(closedTop, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.banners, isNot(contains(HistoryBanner.clearError)));
    });

    testWidgets('a menu route on top (More options reopened) when it hits '
        '0: no throw, nothing left half-open', (tester) async {
      copies(3);
      await show(tester);
      await openClear(tester);
      final ctx = tester.element(find.byType(AlertDialog));
      unawaited(
        showMenu<void>(
          context: ctx,
          position: const RelativeRect.fromLTRB(100, 100, 100, 100),
          items: const [PopupMenuItem<void>(child: Text('A menu'))],
        ),
      );
      await settle(tester);
      service.clear();
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(find.text('Clear all history?'), findsNothing);
    });

    testWidgets('the screen is removed while the dialog closes at 0: no '
        'throw, no listener left behind', (tester) async {
      copies(3);
      await show(tester);
      await openClear(tester);
      service.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      // ignore: invalid_use_of_protected_member
      expect(service.hasListeners, isFalse);
    });

    testWidgets(
      '15 dialogs closed every way (Cancel, Escape, Clear, auto-close '
      'at 0): no listener survives the screen',
      (tester) async {
        copies(4);
        await show(tester);
        for (var i = 0; i < 15; i++) {
          while (service.items.length < 3) {
            source.copy('r$i-${service.items.length}');
          }
          await settle(tester);
          await openClear(tester);
          switch (i % 4) {
            case 0:
              await tester.tap(find.text('Cancel'));
            case 1:
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            case 2:
              await tester.tap(
                find.widgetWithText(FilledButton, 'Clear history'),
              );
            default:
              service.clear();
          }
          await settle(tester);
          expect(find.byType(AlertDialog), findsNothing, reason: 'round $i');
          expect(tester.takeException(), isNull, reason: 'round $i');
        }
        await tester.pumpWidget(const SizedBox());
        // ignore: invalid_use_of_protected_member
        expect(service.hasListeners, isFalse, reason: 'a listener leaked');
      },
    );

    testWidgets('never on a failed clear or a failed read: the dialog stays '
        'open while items remain, even when the count read fails', (
      tester,
    ) async {
      copies(4);
      await show(tester);
      store.failCount = true;
      await openClear(tester);
      source.copy('a copy');
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(clearText(5), findsOneWidget);
      store.failClear = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await settle(tester);
      expect(service.items, hasLength(5), reason: 'a failed clear emptied it');
      expect(service.banners, contains(HistoryBanner.clearError));
    });

    testWidgets('keyboard only: opened with Tab and Enter, an auto-close at '
        '0 leaves the focus where Cancel does (compared run against run)', (
      tester,
    ) async {
      Future<String?> run(bool auto) async {
        service.dispose();
        create();
        copies(3);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        // Keyboard only: focus the More options button and open the menu.
        final more = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is PopupMenuButton && w.tooltip == 'More options',
          ),
          matching: find.byType(IconButton),
        );
        for (var i = 0; i < 40; i++) {
          final ctx = FocusManager.instance.primaryFocus?.context;
          if (ctx != null &&
              ctx.findAncestorWidgetOfExactType<PopupMenuButton<Object?>>() !=
                  null) {
            break;
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(more, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(find.text('Clear all history?'), findsOneWidget);
        if (auto) {
          service.clear();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter); // Cancel
        }
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        return focusSignature();
      }

      final viaCancel = await run(false);
      final viaAuto = await run(true);
      expect(viaAuto, viaCancel, reason: 'the focus lands elsewhere');
      expect(viaAuto, isNotNull, reason: 'the focus is lost');
    });
  });

  // -------------------------------------------- Keep: 0 <-> 1 <-> unknown

  group('Keep dialog: "Set limit" at 0 and the toggles', () {
    /// Puts the history at [n] items, [fail] making the count unreadable, and
    /// lets the open dialog follow (a notification).
    Future<void> goTo(WidgetTester tester, int n, {bool fail = false}) async {
      store.failCount = fail;
      while (service.items.length < n) {
        source.copy('g${service.items.length}');
      }
      while (service.items.length > n) {
        service.delete(service.items.first.id);
      }
      if (service.items.length == n) {
        // Make sure the dialog is told even when n did not change.
        service.setLimit(service.limit);
      }
      await settle(tester);
    }

    void expectState(WidgetTester tester, int? removed, String step) {
      if (removed == null) {
        expect(find.text(unknown), findsOneWidget, reason: step);
        expect(deleteLabel(tester), 'Delete', reason: step);
        expect(deleteButton(tester).onPressed, isNull, reason: step);
      } else if (removed == 0) {
        expect(keepZero(), findsOneWidget, reason: step);
        expect(deleteLabel(tester), 'Set limit', reason: step);
        expect(deleteButton(tester).onPressed, isNotNull, reason: step);
        expect(find.textContaining('0 older'), findsNothing, reason: step);
        expect(find.textContaining('Delete 0'), findsNothing, reason: step);
      } else {
        expect(keepText(removed), findsOneWidget, reason: step);
        expect(
          deleteLabel(tester),
          'Delete $removed ${noun(removed)}',
          reason: step,
        );
        expect(deleteButton(tester).onPressed, isNotNull, reason: step);
      }
    }

    testWidgets('0 <-> 1 <-> unknown <-> 0 <-> 2 <-> unknown <-> 1: the '
        'text, the button, its label and its enabled state agree at every '
        'step', (tester) async {
      final handle = tester.ensureSemantics();
      copies(11);
      await show(tester);
      await lowerLimitTo(tester, 10);
      expectState(tester, 1, 'open at 1');
      final steps = <(int count, bool fail, int? removed)>[
        (10, false, 0),
        (11, false, 1),
        (11, true, null),
        (10, false, 0),
        (12, false, 2),
        (12, true, null),
        (11, false, 1),
        (9, false, 0),
        (9, true, null),
        (10, false, 0),
      ];
      for (final (count, fail, removed) in steps) {
        await goTo(tester, count, fail: fail);
        expectState(tester, removed, 'count=$count fail=$fail');
        final node = tester.getSemantics(deleteFinder());
        expect(
          node.label,
          removed == null
              ? 'Delete'
              : removed == 0
              ? 'Set limit'
              : 'Delete $removed ${noun(removed)}',
        );
        expect(
          node.flagsCollection.isEnabled,
          removed == null ? ui.Tristate.isFalse : ui.Tristate.isTrue,
        );
      }
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      handle.dispose();
    });

    /// Opens the Keep dialog at 12 items and takes two away: known 0.
    Future<void> atZero(WidgetTester tester, {int items = 12}) async {
      copies(items);
      await show(tester);
      await lowerLimitTo(tester, 10);
      while (service.items.length > 10) {
        service.delete(service.items.first.id);
      }
      await settle(tester);
    }

    testWidgets('"Set limit" by Tab and Enter: it sets the limit and '
        'deletes nothing, and the field then shows it', (tester) async {
      await atZero(tester);
      expect(keepZero(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 10);
      expect(service.items, hasLength(10));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(LimitField),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '10',
      );
    });

    testWidgets('"Set limit" by Tab and Space', (tester) async {
      await atZero(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(service.limit, 10);
      expect(service.items, hasLength(10));
    });

    testWidgets('Enter on the default focus (Cancel) at 0 keeps the old '
        'limit', (tester) async {
      await atZero(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      // Enter reached Cancel, not a row behind the dialog (BUG-D1).
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 200);
      expect(service.items, hasLength(10));
    });

    testWidgets('after "Set limit" the limit field works for a second, '
        'lower change, and a raise', (tester) async {
      copies(14);
      await show(tester);
      await lowerLimitTo(tester, 12);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 items'));
      await settle(tester);
      expect(service.limit, 12);
      expect(service.items, hasLength(12));
      await lowerLimitTo(tester, 11);
      expect(find.widgetWithText(FilledButton, 'Delete 1 item'), findsOne);
      while (service.items.length > 11) {
        service.delete(service.items.first.id);
      }
      await settle(tester);
      expect(
        find.text('Keep only the newest 11 items? No items will be deleted.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Set limit'));
      await settle(tester);
      expect(service.limit, 11);
      expect(service.items, hasLength(11));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(LimitField),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '11',
      );
      await lowerLimitTo(tester, 300);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 300);
    });

    testWidgets('a copy arrives while "Set limit" is showing and pushes the '
        'count over the limit: the button turns back into "Delete N" before '
        'the click', (tester) async {
      await atZero(tester, items: 11);
      expect(keepZero(), findsOneWidget);
      copies(3, 100);
      await settle(tester);
      expect(keepText(3), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Delete 3 items'), findsOne);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete 3 items'));
      await settle(tester);
      expect(service.items, hasLength(10));
    });

    testWidgets('a click on "Set limit" in the very frame a copy pushes the '
        'count over the limit: the limit is set and the history is trimmed to '
        'it (what was over is what is deleted)', (tester) async {
      await atZero(tester, items: 11);
      copies(3, 100);
      await tester.tap(find.widgetWithText(FilledButton, 'Set limit'));
      await settle(tester);
      expect(service.limit, 10);
      expect(service.items.length, lessThanOrEqualTo(10));
    });
  });

  group('focus stays in the dialogs when the count changes', () {
    testWidgets('BUG-D1: with the Keep dialog open, a copy arrives (the '
        'dialog rebuilds): Escape still closes it, and Tab and Enter never '
        'act on the history rows behind it (today the focus leaves the '
        'dialog: Escape does nothing and Tab + Enter deleted a row)', (
      tester,
    ) async {
      copies(13);
      await show(tester);
      await lowerLimitTo(tester, 10);
      source.copy('the count changes while the dialog is open');
      await settle(tester);
      final before = service.items.length;
      // Tab, Tab from Cancel is back on Cancel (the dialog has two
      // controls): Enter then closes it and touches nothing. Three Tabs
      // would be on the dialog's own "Delete 4 items", and Enter there is
      // its confirm, not a row behind it.
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing, reason: 'Enter on Cancel');
      expect(
        service.items.length,
        before,
        reason:
            'a row behind the dialog '
            'was deleted with the keyboard',
      );
      expect(service.limit, 200);
      // Again with three Tabs and Escape: it closes, whatever Tab reached.
      await lowerLimitTo(tester, 10);
      source.copy('another while open');
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing, reason: 'Escape');
      expect(service.items.length, before + 1);
      expect(service.limit, 200);
    });

    testWidgets('the Clear history dialog keeps the focus inside when a '
        'copy arrives: Escape closes it and nothing behind is touched', (
      tester,
    ) async {
      copies(4);
      await show(tester);
      await openClear(tester);
      source.copy('arrives while open');
      await settle(tester);
      final before = service.items.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.items.length, before);
    });
  });
}

class _Store extends MemoryHistoryStore {
  bool failCount = false;
  bool failClear = false;

  @override
  int countRemovedBy(int newLimit) {
    if (failCount) throw const FileSystemException('read failed');
    return super.countRemovedBy(newLimit);
  }

  @override
  int clear() {
    if (failClear) throw const FileSystemException('clear failed');
    return super.clear();
  }
}
