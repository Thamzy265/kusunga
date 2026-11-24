import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/picker/picker_controller.dart';
import '../picker/fake_picker_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';
import '../support/main_tabs.dart';

/// Tester round 17 on 578ee22 (D2, D3, D4): a closed dialog or menu gives the
/// focus back to its opener; nothing behind a modal takes it. Breaking the
/// return, the dropped requests, the opener's own node and the nested routes.
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

  /// Clicks the first History row fully in view, on its text.
  Future<void> clickFirstVisibleRow(WidgetTester tester) async {
    final vp = tester.getRect(find.byType(Viewport));
    final rows =
        [
            for (final e in find.byType(HistoryRow).evaluate())
              tester.getRect(find.byWidget(e.widget)),
          ].where((r) => r.top >= vp.top && r.bottom <= vp.bottom).toList()
          ..sort((a, b) => a.top.compareTo(b.top));
    await tester.tapAt(rows.first.topLeft + const Offset(60, 16));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  Finder field() => find.descendant(
    of: find.byType(LimitField),
    matching: find.byType(TextField),
  );

  /// Who has the focus: inside a dialog, on a History row (or one of its
  /// buttons), inside the page behind, or nothing.
  String where() {
    final n = FocusManager.instance.primaryFocus;
    final ctx = n?.context;
    if (ctx == null) return 'nothing';
    if (ctx.findAncestorWidgetOfExactType<AlertDialog>() != null) {
      return 'dialog';
    }
    if (ctx.findAncestorWidgetOfExactType<PopupMenuButton<Object?>>() != null) {
      return 'more-button';
    }
    if (ctx.findAncestorWidgetOfExactType<HistoryRow>() != null) return 'row';
    if (ctx.findAncestorWidgetOfExactType<TextField>() != null) return 'field';
    return 'other(${ctx.widget.runtimeType})';
  }

  Future<void> openClearByMouse(WidgetTester tester) async {
    await showHistoryTab(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
  }

  /// Enter in the Keep field first (the field unfocuses itself, leaving the
  /// History scope without a focused child), then Clear by mouse.
  Future<void> openClearAfterEnterInField(WidgetTester tester) async {
    await showKeepField(tester);
    await tester.tap(field());
    await tester.pump();
    await showKeepField(tester);
    await tester.enterText(field(), '200');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await openClearByMouse(tester);
  }

  Future<void> openClearByKeyboard(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      if (where() == 'more-button') break;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
    }
    expect(where(), 'more-button');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
  }

  Future<void> openKeep(WidgetTester tester, int to) async {
    await showKeepField(tester);
    await tester.tap(field());
    await tester.pump();
    await showKeepField(tester);
    await tester.enterText(field(), '$to');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> shiftTab(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
  }

  /// Opens the Keep dialog by typing [to] and leaving the field with Tab
  /// (the commit on focus loss).
  Future<void> openKeepByTabOut(WidgetTester tester, int to) async {
    await showKeepField(tester);
    await tester.tap(field());
    await tester.pump();
    await showKeepField(tester);
    await tester.enterText(field(), '$to');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  /// Opens the Keep dialog by typing [to] and clicking elsewhere (the commit
  /// on focus loss by mouse).
  Future<void> openKeepByBlur(WidgetTester tester, int to) async {
    await showKeepField(tester);
    await tester.tap(field());
    await tester.pump();
    await showKeepField(tester);
    await tester.enterText(field(), '$to');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  /// What happens while a dialog is open.
  final meanwhile = <String, Future<void> Function(WidgetTester)>{
    'nothing': (t) async {},
    'a copy': (t) async {
      source.copy('while open');
      await t.pumpAndSettle();
    },
    'a burst of 20': (t) async {
      copies(20, 500);
      await t.pumpAndSettle();
    },
    'the first row deleted': (t) async {
      service.delete(service.items.first.id);
      await t.pumpAndSettle();
    },
    'the Mac setup card appears': (t) async {
      source.access = PasteAccess.needsSetup;
      await t.runAsync(() => service.recheckPasteAccess());
      await t.pumpAndSettle();
    },
  };

  // ------------------------------------------------- the return, every path

  group('Keep dialog gives the focus back to the Keep field', () {
    final openers = <String, Future<void> Function(WidgetTester)>{
      'Enter in the field': (t) => openKeep(t, 10),
      'Tab out of the field': (t) => openKeepByTabOut(t, 10),
      'a click elsewhere': (t) => openKeepByBlur(t, 10),
    };
    final closers = <String, Future<void> Function(WidgetTester)>{
      'Cancel by click': (t) async => t.tap(find.text('Cancel')),
      'Cancel by Enter': (t) async => t.sendKeyEvent(LogicalKeyboardKey.enter),
      'Escape': (t) async => t.sendKeyEvent(LogicalKeyboardKey.escape),
      'confirm by click': (t) async => t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      ),
    };
    for (final MapEntry(key: oName, value: open) in openers.entries) {
      for (final MapEntry(key: cName, value: close) in closers.entries) {
        testWidgets('opened by $oName, closed by $cName: back in the field, '
            'whatever happened meanwhile', (tester) async {
          for (final MapEntry(key: mName, value: event) in meanwhile.entries) {
            service.dispose();
            create();
            copies(14);
            await tester.pumpWidget(const SizedBox());
            await show(tester);
            await open(tester);
            expect(find.byType(AlertDialog), findsOneWidget, reason: mName);
            await event(tester);
            await close(tester);
            await settle(tester);
            expect(find.byType(AlertDialog), findsNothing, reason: mName);
            expect(where(), 'field', reason: '$cName after $mName');
            expect(tester.takeException(), isNull, reason: mName);
          }
        });
      }
    }

    testWidgets('after Tab-out + Cancel, Tab and Shift+Tab leave the field '
        'normally and the dialog never comes back (no loop, no trap)', (
      tester,
    ) async {
      copies(14);
      await show(tester);
      await openKeepByTabOut(tester, 10);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(where(), 'field');
      expect(tester.widget<TextField>(field()).controller!.text, '200');
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing, reason: 'Tab $i');
      }
      for (var i = 0; i < 6; i++) {
        await shiftTab(tester);
        expect(find.byType(AlertDialog), findsNothing, reason: 'Shift+Tab $i');
      }
      expect(service.limit, 200);
      expect(service.items, hasLength(14));
    });

    testWidgets('Tab-out + confirm: the limit is set, the focus is in the '
        'field, and leaving the field again opens nothing', (tester) async {
      copies(14);
      await show(tester);
      await openKeepByTabOut(tester, 10);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await settle(tester);
      expect(service.limit, 10);
      expect(where(), 'field');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await shiftTab(tester);
      await shiftTab(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Tab-out with an unknown count: the dialog, Cancel, back in '
        'the field, no loop', (tester) async {
      copies(14);
      await show(tester);
      store.failCount = true;
      await openKeepByTabOut(tester, 10);
      expect(find.text("Couldn't count the items. Try again."), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(where(), 'field');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Escape pressed while the dialog opens (animations on): '
        'back in the field, no exception', (tester) async {
      copies(14);
      await show(tester, animate: true);
      await openKeep(tester, 10);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(where(), 'field');
      expect(tester.takeException(), isNull);
    });
  });

  group('Clear history gives the focus back to More options', () {
    final openers = <String, Future<void> Function(WidgetTester)>{
      'the mouse': openClearByMouse,
      'the keyboard (menu)': openClearByKeyboard,
      'a click after Enter in the Keep field': openClearAfterEnterInField,
    };
    final closers = <String, Future<void> Function(WidgetTester)>{
      'Cancel by click': (t) async => t.tap(find.text('Cancel')),
      'Cancel by Enter': (t) async => t.sendKeyEvent(LogicalKeyboardKey.enter),
      'Escape': (t) async => t.sendKeyEvent(LogicalKeyboardKey.escape),
      'confirm by click': (t) async =>
          t.tap(find.widgetWithText(FilledButton, 'Clear history')),
      'the history reaching 0 (auto-close)': (t) async => service.clear(),
    };
    for (final MapEntry(key: oName, value: open) in openers.entries) {
      for (final MapEntry(key: cName, value: close) in closers.entries) {
        testWidgets('opened with $oName, closed by $cName: back on More '
            'options, whatever happened meanwhile', (tester) async {
          for (final MapEntry(key: mName, value: event) in meanwhile.entries) {
            service.dispose();
            create();
            copies(14);
            await tester.pumpWidget(const SizedBox());
            await show(tester);
            await open(tester);
            expect(find.byType(AlertDialog), findsOneWidget, reason: mName);
            await event(tester);
            await close(tester);
            await settle(tester);
            expect(find.byType(AlertDialog), findsNothing, reason: mName);
            expect(where(), 'more-button', reason: '$cName after $mName');
            expect(tester.takeException(), isNull, reason: mName);
          }
        });
      }
    }

    testWidgets('the More menu dismissed by Escape or by a click outside '
        'gives the focus back to More options', (tester) async {
      copies(5);
      await show(tester);
      for (final how in ['Escape', 'click outside']) {
        await showHistoryTab(tester);
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        expect(find.text('Clear history'), findsOneWidget);
        if (how == 'Escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tapAt(const Offset(5, 600));
        }
        await settle(tester);
        expect(find.text('Clear history'), findsNothing, reason: how);
        expect(where(), 'more-button', reason: how);
      }
    });

    testWidgets('the More menu dismissed while copies arrive and the first '
        'row changes: back on More options, no row steals it', (tester) async {
      copies(5);
      await show(tester);
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        source.copy('during $i');
        service.delete(service.items.last.id);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(where(), 'more-button');
    });
  });

  // ------------------------------------------------------- dropped requests

  group('dropped scroll-and-focus requests leave nothing wrong behind', () {
    Future<void> menuNow(WidgetTester tester) async {
      (tester.state(find.byType(PopupMenuButton<Object?>))
              as PopupMenuButtonState<Object?>)
          .showButtonMenu();
    }

    testWidgets('End dropped by a menu: after Escape the focus is on More '
        'options, and a later End and Home still work from a row', (
      tester,
    ) async {
      service.dispose();
      create(limit: 5000);
      copies(400);
      await show(tester);
      await tester.tap(find.byType(HistoryRow).first, warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await menuNow(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(where(), 'more-button');
      // Scroll back to the top by the wheel, click the first row, End, Home.
      final mouse = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byType(CustomScrollView))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -90000)));
      await settle(tester);
      await clickFirstVisibleRow(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await settle(tester);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<HistoryRow>()
            ?.item
            .id,
        service.items.last.id,
        reason: 'a later End does not work',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await settle(tester);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<HistoryRow>()
            ?.item
            .id,
        service.items.first.id,
        reason: 'a later Home does not work',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a text-size change while the menu opens in the same frame: '
        'no row stays held after the menu closes, no exception', (
      tester,
    ) async {
      copies(60);
      final scale = ValueNotifier<double>(1);
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          builder: (context, child) => ValueListenableBuilder<double>(
            valueListenable: scale,
            builder: (context, s, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(s),
              ),
              child: child!,
            ),
          ),
          home: HistoryHost(history: Future.value(service), initial: service),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(HistoryRow).at(3), warnIfMissed: false);
      await tester.pump();
      scale.value = 2;
      await menuNow(tester);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      final held = tester
          .widgetList<HistoryRow>(find.byType(HistoryRow, skipOffstage: false))
          .where((r) => r.keepAlive);
      expect(held, isEmpty, reason: 'a row is still held');
      expect(
        find.byType(HistoryRow, skipOffstage: false).evaluate().length,
        lessThan(50),
      );
      // A later text-size change with a row focused still keeps the focus.
      await tester.tap(find.byType(HistoryRow).first, warnIfMissed: false);
      await tester.pump();
      final id = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<HistoryRow>()
          ?.item
          .id;
      scale.value = 1;
      await settle(tester);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<HistoryRow>()
            ?.item
            .id,
        id,
        reason: 'the text-size hold no longer restores the focus',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the focused row is deleted while the menu is open (a '
        'survivor request is dropped): the list stays right and arrow keys '
        'work afterwards', (tester) async {
      copies(30);
      await show(tester);
      await tester.tap(find.byType(HistoryRow).at(2), warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final focusedId = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<HistoryRow>()
          ?.item
          .id;
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      service.delete(focusedId!);
      await tester.pumpAndSettle();
      expect(where(), isNot('row'), reason: 'a survivor row took the focus');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(where(), 'more-button');
      await tester.tap(find.byType(HistoryRow).at(2), warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(where(), 'row', reason: 'arrow keys no longer work');
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------- the opener's wrapper node

  group('the node above More options is invisible', () {
    testWidgets('it is not a Tab stop, not in the traversal, and adds no '
        'semantics node', (tester) async {
      final handle = tester.ensureSemantics();
      copies(5);
      await show(tester);
      final labelled = FocusManager.instance.rootScope.descendants.where(
        (n) => n.debugLabel == 'More options',
      );
      for (final n in labelled) {
        expect(n.canRequestFocus, isFalse);
        expect(n.skipTraversal, isTrue);
      }
      expect(
        FocusManager.instance.rootScope.traversalDescendants.where(
          (n) => n.debugLabel == 'More options',
        ),
        isEmpty,
      );
      // Tabbing back from the first row: the More button is reached once.
      var moreStops = 0;
      for (var i = 0; i < 12; i++) {
        await shiftTab(tester);
        if (where() == 'more-button') moreStops++;
      }
      expect(moreStops, 1, reason: 'More options is not one Tab stop');
      var nodes = 0;
      void walk(SemanticsNode n) {
        if (n.tooltip == 'More options' || n.label == 'More options') nodes++;
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      // ignore: deprecated_member_use
      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      expect(nodes, 1, reason: 'a second semantics node for More options');
      handle.dispose();
    });

    testWidgets('the Tab order of the header: the tabs, More options, then '
        'the rows (the Keep field moved to Settings in M1.7)', (tester) async {
      copies(3);
      await show(tester);
      final order = <String>[];
      // From the first row, Shift+Tab walks back to the start.
      for (var i = 0; i < 6; i++) {
        await shiftTab(tester);
        final ctx = FocusManager.instance.primaryFocus?.context;
        String? id;
        void check(Widget w) {
          if (id == null && w is Semantics && w.properties.identifier != null) {
            id = w.properties.identifier;
          }
        }

        if (ctx != null) {
          check(ctx.widget);
          ctx.visitAncestorElements((e) {
            check(e.widget);
            return id == null;
          });
        }
        order.add(id ?? where());
      }
      expect(order, containsAllInOrder(['more-button', 'main-tab-settings']));
      expect(order, isNot(contains('field')));
      expect(order.where((e) => e == 'more-button'), hasLength(1));
    });
  });

  // ----------------------------------------------------- nested routes, removal

  group('nested routes and removal', () {
    testWidgets('a second dialog over Clear when it auto-closes at 0: the '
        'one on top keeps the focus, and no return steals it', (tester) async {
      copies(3);
      await show(tester);
      await openClearByMouse(tester);
      final ctx = tester.element(find.byType(AlertDialog));
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: const Text('On top'),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Close top'),
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(where(), 'dialog');
      service.clear();
      await settle(tester);
      expect(find.text('On top'), findsOneWidget);
      expect(find.text('Clear all history?'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<AlertDialog>(),
        isNotNull,
        reason: 'the return took the focus from the dialog on top',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Keep dialog with a second dialog on top: Escape closes '
        'the top one first and the field does not take the focus meanwhile', (
      tester,
    ) async {
      copies(14);
      await show(tester);
      await openKeep(tester, 10);
      final ctx = tester.element(find.byType(AlertDialog));
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (c) => const AlertDialog(title: Text('On top')),
        ),
      );
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('On top'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget, reason: 'Keep still open');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(where(), 'field');
    });

    testWidgets('the screen is removed in the frame a dialog closes: no '
        'exception from a pending return, no listener left', (tester) async {
      for (final which in ['Keep', 'Clear']) {
        service.dispose();
        create();
        copies(14);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        if (which == 'Keep') {
          await openKeep(tester, 10);
        } else {
          await openClearByMouse(tester);
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: which);
        // ignore: invalid_use_of_protected_member
        expect(service.hasListeners, isFalse, reason: which);
      }
    });

    testWidgets('the screen is removed while the menu closes by Escape', (
      tester,
    ) async {
      copies(5);
      await show(tester);
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------- the picker pressed over a dialog

  group('the picker shortcut pressed while a dialog is open', () {
    Future<(FakePickerPort, PickerController)> wire(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = FakePickerPort();
      final controller = PickerController(
        port: port,
        log: FakeLog(),
        isMac: true,
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(service);
      await tester.pumpWidget(
        KusungaApp(history: Future.value(service), picker: controller),
      );
      await tester.pump();
      await tester.pump();
      return (port, controller);
    }

    final dialogs = <String, Future<void> Function(WidgetTester)>{
      'Clear by mouse': openClearByMouse,
      'Clear after Enter in the Keep field': openClearAfterEnterInField,
      'Keep': (t) => openKeep(t, 10),
    };
    final closes =
        <String, Future<void> Function(WidgetTester, FakePickerPort)>{
          'Escape in the picker': (t, p) async =>
              t.sendKeyEvent(LogicalKeyboardKey.escape),
          'the picker loses the focus': (t, p) async => p.dismiss(),
          'Enter pastes the selected row': (t, p) async =>
              t.runAsync(() => t.sendKeyEvent(LogicalKeyboardKey.enter)),
        };
    for (final MapEntry(key: dName, value: open) in dialogs.entries) {
      for (final MapEntry(key: cName, value: close) in closes.entries) {
        testWidgets('$dName open, the picker opens over it and closes by '
            '$cName: the dialog is still there with the focus in it, and '
            'Escape closes it', (tester) async {
          copies(14);
          final (port, _) = await wire(tester);
          await open(tester);
          expect(where(), 'dialog');
          port.press();
          await tester.pump();
          await tester.pump();
          expect(find.text('Search history…'), findsOneWidget);
          await close(tester, port);
          await tester.pump();
          await tester.pump();
          await tester.pumpAndSettle();
          expect(find.text('Search history…'), findsNothing);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(where(), 'dialog', reason: 'the focus is in ${where()}');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester);
          expect(
            find.byType(AlertDialog),
            findsNothing,
            reason: 'Escape did not close the dialog',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('pressing the shortcut again while the picker is open keeps '
        'it open, and then Escape closes the picker first and the dialog '
        'second', (tester) async {
      copies(14);
      final (port, _) = await wire(tester);
      await openKeep(tester, 10);
      port.press();
      await tester.pump();
      await tester.pump();
      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.text('Search history…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Search history…'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
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
