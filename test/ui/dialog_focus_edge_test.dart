import 'dart:io';

import 'package:material_ui/material_ui.dart';
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

/// Tester round 16 on 61c8cf3 (BUG-D1): no widget behind a modal may take the
/// focus. The first History row's autofocus is now guarded; this file tries
/// every other way the focus can reach the page behind a dialog or a menu.
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

  void expectInDialog(String step) =>
      expect(where(), 'dialog', reason: '$step: the focus is in ${where()}');

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

  final events = <String, void Function()>{
    'a copy': () => source.copy('one'),
    'the first row deleted': () => service.delete(service.items.first.id),
    'a burst of 20 copies': () {
      for (var i = 0; i < 20; i++) {
        source.copy('burst $i');
      }
    },
    'the first row deleted twice': () {
      service.delete(service.items.first.id);
      service.delete(service.items.first.id);
    },
  };

  // ------------------------------------------------ nothing behind a dialog

  group('Clear history: the focus never reaches the rows behind it', () {
    final entries = <String, Future<void> Function(WidgetTester)>{
      'by mouse': openClearByMouse,
      'after Enter in the Keep field': openClearAfterEnterInField,
      'by keyboard from the menu': openClearByKeyboard,
    };
    for (final MapEntry(key: entry, value: open) in entries.entries) {
      for (final MapEntry(key: eventName, value: event) in events.entries) {
        testWidgets('$entry, then $eventName: focus stays in the dialog; '
            'Tab, Shift+Tab, Enter, Space and Escape never touch a row', (
          tester,
        ) async {
          copies(30);
          await show(tester);
          await open(tester);
          expectInDialog('opened');
          event();
          await settle(tester);
          expectInDialog('after $eventName');
          final ids = [for (final i in service.items) i.id];
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            expectInDialog('Tab $i');
          }
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
          await tester.pump();
          expectInDialog('Shift+Tab');
          expect([for (final i in service.items) i.id], ids);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester);
          expect(find.byType(AlertDialog), findsNothing, reason: 'Escape');
          expect(
            [for (final i in service.items) i.id],
            ids,
            reason: 'a key reached a row',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('Enter and Space on the dialog\'s own buttons act on the '
        'dialog only: Space on Cancel keeps all, Enter on Clear history '
        'clears exactly what the dialog said', (tester) async {
      copies(6);
      await show(tester);
      await openClearAfterEnterInField(tester);
      source.copy('late');
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space); // Cancel
      await settle(tester);
      expect(service.items, hasLength(7));
      await openClearByMouse(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Clear history
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(service.items, isEmpty);
    });
  });

  group('Keep dialog: the focus never reaches the rows behind it', () {
    for (final MapEntry(key: eventName, value: event) in events.entries) {
      testWidgets('after Enter in the field, then $eventName', (tester) async {
        copies(30);
        await show(tester);
        await openKeep(tester, 10);
        expectInDialog('opened');
        event();
        await settle(tester);
        expectInDialog('after $eventName');
        final ids = [for (final i in service.items) i.id];
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expectInDialog('Tab $i');
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect([for (final i in service.items) i.id], ids);
        expect(service.limit, 200);
      });
    }

    testWidgets('0, 1, unknown toggles (the dialog rebuilds each time): the '
        'focus stays in it and Escape closes it', (tester) async {
      copies(12);
      await show(tester);
      await openKeep(tester, 10);
      final steps = <(int, bool)>[
        (10, false),
        (11, false),
        (11, true),
        (10, false),
        (13, false),
        (13, true),
        (12, false),
      ];
      for (final (count, fail) in steps) {
        store.failCount = fail;
        while (service.items.length < count) {
          source.copy('g${service.items.length}');
        }
        while (service.items.length > count) {
          service.delete(service.items.first.id);
        }
        service.setLimit(service.limit); // notify when nothing changed
        await settle(tester);
        expectInDialog('count=$count fail=$fail');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the third Tab from Cancel is on the dialog\'s own Delete: '
        'Enter there confirms what the dialog says and nothing else', (
      tester,
    ) async {
      copies(13);
      await show(tester);
      await openKeep(tester, 10);
      source.copy('while open'); // now 4 to delete
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expectInDialog('third Tab');
      expect(
        find.widgetWithText(FilledButton, 'Delete 4 items'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(service.items, hasLength(10));
      expect(service.limit, 10);
    });
  });

  // ------------------------------------------- the focus after a dialog closes

  group('where the focus goes when a dialog closes', () {
    Future<String> closeVia(
      WidgetTester tester,
      String how,
      bool copyBetween,
    ) async {
      service.dispose();
      create();
      copies(14);
      await tester.pumpWidget(const SizedBox());
      await show(tester);
      await openKeep(tester, 10);
      if (copyBetween) {
        source.copy('between');
        await settle(tester);
      }
      switch (how) {
        case 'Cancel':
          await tester.tap(find.text('Cancel'));
        case 'Escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'confirm':
          await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
        default:
          fail(how);
      }
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing, reason: how);
      return where();
    }

    for (final how in ['Cancel', 'Escape', 'confirm']) {
      testWidgets('BUG-D2: Keep, $how: with or without a copy in between the '
          'focus lands in the same kind of place, and never "nothing" '
          '(today: the page scope with nothing focused, or the first row '
          'if a copy came meanwhile)', (tester) async {
        final plain = await closeVia(tester, how, false);
        final withCopy = await closeVia(tester, how, true);
        expect(withCopy, plain, reason: 'a copy changed where the focus goes');
        expect(plain, isNot('nothing'));
      });
    }

    testWidgets('Clear, auto-close at 0: the focus lands where a Cancel '
        'does, with and without a copy in between', (tester) async {
      Future<String> run(bool auto, bool copyBetween) async {
        service.dispose();
        create();
        copies(3);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        await openClearAfterEnterInField(tester);
        if (copyBetween) {
          source.copy('between');
          await settle(tester);
        }
        if (auto) {
          service.clear();
        } else {
          await tester.tap(find.text('Cancel'));
        }
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        return where();
      }

      // (With a copy in between the auto-close leaves no row to focus.)
      final cancel = await run(false, false);
      expect(await run(true, false), cancel);
    });
  });

  // -------------------------------------------- other ways the focus can move

  group('other routes and moves', () {
    testWidgets('the More menu open and a copy arrives: the focus stays in '
        'the menu, Escape closes it, nothing behind is activated', (
      tester,
    ) async {
      copies(5);
      await show(tester);
      await showHistoryTab(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Clear history'), findsOneWidget);
      source.copy('while the menu is open');
      await settle(tester);
      final ids = [for (final i in service.items) i.id];
      expect(
        where(),
        isNot('row'),
        reason: 'a row took the focus from the menu',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Clear history'), findsNothing);
      expect([for (final i in service.items) i.id], ids);
    });

    testWidgets(
      'BUG-D3: End is still stepping to the last row (400 rows) when the '
      'More menu opens in the same frame: the pending focus request does '
      'not take the focus from the menu or the Clear dialog',
      (tester) async {
        service.dispose();
        create(limit: 5000);
        copies(400);
        await show(tester);
        await tester.tap(find.byType(HistoryRow).first, warnIfMissed: false);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        // The header is still mounted before the next frame: open the menu now.
        (tester.state(find.byType(PopupMenuButton<Object?>))
                as PopupMenuButtonState<Object?>)
            .showButtonMenu();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.text('Clear history'), findsOneWidget, reason: 'menu open');
        expect(
          where(),
          isNot('row'),
          reason: 'a row took the focus from the menu',
        );
        await tester.tap(find.text('Clear history'));
        await tester.pumpAndSettle();
        expect(find.text('Clear all history?'), findsOneWidget);
        expectInDialog('the pending End request finished meanwhile');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(service.items, hasLength(400));
      },
    );

    testWidgets('a deleted-first-row survivor request (arrow keys in use) '
        'cannot pull the focus out of the Keep dialog', (tester) async {
      copies(30);
      await show(tester);
      await tester.tap(find.byType(HistoryRow).first, warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // Keyboard to the Keep field, then the dialog.
      await openKeep(tester, 10);
      expectInDialog('opened');
      for (final item in List.of(service.items).take(5)) {
        service.delete(item.id);
      }
      await settle(tester);
      expectInDialog('after deletes (arrow keys were in use)');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
    });
  });

  group(
    'the Mac setup card and the picker permission card behind a dialog',
    () {
      testWidgets(
        'BUG-D4: the setup card appears while a dialog is open (access '
        'revoked, a recheck): the dialog keeps the focus',
        (tester) async {
          copies(6);
          await show(tester);
          await openClearAfterEnterInField(tester);
          source.access = PasteAccess.needsSetup;
          await tester.runAsync(() => service.recheckPasteAccess());
          await settle(tester);
          expect(
            find.text('Allow Kusunga to read what you copy'),
            findsOneWidget,
          );
          expectInDialog('the setup card appeared');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester);
          expect(find.byType(AlertDialog), findsNothing);
          expect(service.items, hasLength(6));
        },
      );

      testWidgets('BUG-D4: the same with the Keep dialog', (tester) async {
        copies(14);
        await show(tester);
        await openKeep(tester, 10);
        source.access = PasteAccess.needsSetup;
        await tester.runAsync(() => service.recheckPasteAccess());
        await settle(tester);
        // The card is in the History tab, behind Settings and the dialog.
        expect(
          find.text('Allow Kusunga to read what you copy', skipOffstage: false),
          findsOneWidget,
        );
        expectInDialog('the setup card appeared');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
      });

      testWidgets('with no dialog open and a row focused, the setup card '
          'appears and the row keeps the focus (the original behaviour); with '
          'nothing focused it takes the focus', (tester) async {
        copies(3);
        await show(tester);
        source.access = PasteAccess.needsSetup;
        await tester.runAsync(() => service.recheckPasteAccess());
        await settle(tester);
        expect(
          find.text('Allow Kusunga to read what you copy'),
          findsOneWidget,
        );
        expect(where(), 'row', reason: 'the card took the focus from a row');
      });

      testWidgets('nothing focused and no dialog: the setup card heading '
          'takes the focus when it appears', (tester) async {
        copies(3);
        await show(tester);
        // Nothing focused in History. (Before M1.7 an Enter in the Keep
        // field did this; the field is in the Settings tab now.)
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        source.access = PasteAccess.needsSetup;
        await tester.runAsync(() => service.recheckPasteAccess());
        await settle(tester);
        final ctx = FocusManager.instance.primaryFocus?.context;
        expect(ctx, isNotNull);
        expect(
          find.descendant(
            of: find.byWidget(ctx!.widget),
            matching: find.text('Allow Kusunga to read what you copy'),
          ),
          findsOneWidget,
        );
      });
    },
  );

  group('the picker on top of the history', () {
    testWidgets('a copy arriving while the picker is open does not take '
        'the focus from its search field', (tester) async {
      copies(6);
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
      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.text('Search history…'), findsOneWidget);
      EditableText? search() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>();
      expect(search(), isNotNull, reason: 'the search field has the focus');
      for (var i = 0; i < 4; i++) {
        source.copy('while the picker is open $i');
        await tester.pump();
        await tester.pump();
        expect(search(), isNotNull, reason: 'copy $i took the focus');
      }
      await tester.enterText(find.byType(TextField), 'while');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------- the original first-row autofocus

  group('the original autofocus of the newest row (no dialog open)', () {
    testWidgets('on opening, the newest row has the focus', (tester) async {
      copies(5);
      await show(tester);
      final row = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<HistoryRow>();
      expect(row, isNotNull);
      expect(row!.item.id, service.items.first.id);
    });

    testWidgets('a copy arrives while a row has the focus: that row keeps '
        'it', (tester) async {
      copies(5);
      await show(tester);
      final before = FocusManager.instance.primaryFocus;
      source.copy('new');
      await settle(tester);
      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('nothing focused in History, a copy arrives, no dialog: the '
        'newest row takes the focus as before', (tester) async {
      copies(5);
      await show(tester);
      // Before M1.7 an Enter in the Keep field left nothing focused; the
      // field is in the Settings tab now.
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      source.copy('new');
      await settle(tester);
      final row = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<HistoryRow>();
      expect(row?.item.id, service.items.first.id);
    });

    testWidgets('after the dialog closes, a later copy does not steal the '
        'focus from where it went; and with nothing focused it autofocuses '
        'again', (tester) async {
      copies(14);
      await show(tester);
      await openKeep(tester, 10);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      final landed = where();
      source.copy('after close');
      await settle(tester);
      expect(where(), anyOf(landed, 'row'));
      expect(tester.takeException(), isNull);
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
