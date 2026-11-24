import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late FlakyStore store;
  late HistoryService service;
  late List<String> written;
  var now = 0;

  HistoryService makeService({Set<HistoryNotice> notices = const {}}) =>
      HistoryService(
        store: store,
        source: source,
        log: const NullErrorLog(),
        notices: notices,
        clock: () => now += 10,
        writeClipboard: (t) async => written.add(t),
      )..start();

  Widget app(
    HistoryService s, {
    Brightness brightness = Brightness.light,
    bool disableAnimations = false,
    bool settings = false,
  }) => MaterialApp(
    theme: KusungaTokens.themeData(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: settings
        ? SettingsScreen(service: s, onShowPrivacy: () {})
        : HistoryScreen(service: s, now: () => now),
  );

  Future<void> show(WidgetTester tester, [HistoryService? s]) async {
    await tester.pumpWidget(app(s ?? service));
    await tester.pump();
  }

  void copyTexts(List<String> texts) {
    for (final t in texts) {
      source.copy(t);
    }
  }

  setUp(() {
    now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
    source = FakeClipboardSource();
    store = FlakyStore(MemoryHistoryStore());
    written = [];
    service = makeService();
  });
  tearDown(() => service.dispose());

  group('states', () {
    testWidgets('empty: message, 0 of 200, Clear history disabled', (
      tester,
    ) async {
      await show(tester);

      expect(find.text('History'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.text('Copy some text in any app and it will appear here.'),
        findsOneWidget,
      );
      expect(find.text('0 of 200 items'), findsOneWidget);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.widgetWithText(PopupMenuItem<Object?>, 'Clear history'),
      );
      expect(item.enabled, isFalse);
    });

    testWidgets('a copy appears at the top at once', (tester) async {
      await show(tester);
      copyTexts(['hello', 'https://example.com/a']);
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet'), findsNothing);
      final top = tester.getTopLeft(find.text('https://example.com/a')).dy;
      final next = tester.getTopLeft(find.text('hello')).dy;
      expect(top, lessThan(next));
    });

    testWidgets(
      'long text is cut to 2 lines and the full text is in the tooltip',
      (tester) async {
        await show(tester);
        final long = List.filled(40, 'word').join(' ');
        copyTexts([long]);
        await tester.pumpAndSettle();

        final text = tester.widget<Text>(
          find.textContaining('word word').first,
        );
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(find.byTooltip(long), findsOneWidget);
      },
    );

    testWidgets('bidi characters are shown as symbols in the list', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['safe${String.fromCharCode(0x202E)}txt']);
      await tester.pumpAndSettle();
      expect(find.textContaining('[U+202E]'), findsOneWidget);
    });

    testWidgets('the footer is throttled to one update every 2 seconds', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('0 of 200 items'), findsOneWidget);
      copyTexts(['a']);
      await tester.pump(const Duration(milliseconds: 100));
      copyTexts(['b']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('0 of 200 items'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('2 of 200 items'), findsOneWidget);
    });
  });

  group('banners and setup card', () {
    testWidgets('memory-only, read error, write error and clear error text', (
      tester,
    ) async {
      final s = makeService(
        notices: {HistoryNotice.memoryOnly, HistoryNotice.readError},
      );
      await show(tester, s);
      expect(
        find.text(
          "History won't be kept after you quit, because Kusunga can't reach your keychain.",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Kusunga couldn't read your old history, so it started a new one.",
        ),
        findsOneWidget,
      );

      store.failWrites = true;
      source.copy('x');
      await tester.pump();
      expect(
        find.text("Couldn't save the latest item. Kusunga will try again."),
        findsOneWidget,
      );
      expect(
        find.text('x'),
        findsOneWidget,
        reason: 'in-memory items still show',
      );

      store.failClear = true;
      s.clear();
      await tester.pump();
      expect(find.text("Couldn't clear history. Try again."), findsOneWidget);
      s.dispose();
    });

    testWidgets('incompatible history banner text', (tester) async {
      final s = makeService(notices: {HistoryNotice.incompatible});
      await show(tester, s);
      expect(
        find.text(
          'This history was made by a newer or different version of Kusunga. '
          "It's safe, but this version can't open it. History won't be kept "
          'until you update.',
        ),
        findsOneWidget,
      );
      s.dispose();
    });

    testWidgets('a banner can be dismissed', (tester) async {
      final s = makeService(notices: {HistoryNotice.readError});
      await show(tester, s);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.textContaining('started a new one'), findsNothing);
      s.dispose();
    });

    testWidgets('banners are live regions', (tester) async {
      final handle = tester.ensureSemantics();
      final s = makeService(notices: {HistoryNotice.memoryOnly});
      await show(tester, s);
      var live = false;
      void walk(SemanticsNode n, bool inLive) {
        final isLive = inLive || n.flagsCollection.isLiveRegion;
        if (n.label.contains("won't be kept") && isLive) live = true;
        n.visitChildren((c) {
          walk(c, isLive);
          return true;
        });
      }

      walk(tester.getSemantics(find.byType(Scaffold).first), false);
      expect(live, isTrue);
      s.dispose();
      handle.dispose();
    });

    testWidgets('setup card: heading, steps, and I\'ve done this re-checks', (
      tester,
    ) async {
      source.access = PasteAccess.needsSetup;
      final s = makeService();
      await show(tester, s);
      await tester.pump();

      expect(find.text('Allow Kusunga to read what you copy'), findsOneWidget);
      expect(
        find.text(
          'To keep your history, open System Settings > Privacy & Security > '
          'Paste from Other Apps and choose Allow for Kusunga.',
        ),
        findsOneWidget,
      );

      source.access = PasteAccess.allowed;
      await tester.tap(find.text("I've done this"));
      await tester.pump();
      await tester.pump();
      expect(find.text('Allow Kusunga to read what you copy'), findsNothing);
      s.dispose();
    });

    testWidgets('focus starts on the setup card heading when it shows', (
      tester,
    ) async {
      source.access = PasteAccess.needsSetup;
      final s = makeService();
      await show(tester, s);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!;
      expect(focused.context, isNotNull);
      expect(
        find.descendant(
          of: find.byWidget(focused.context!.widget),
          matching: find.text('Allow Kusunga to read what you copy'),
        ),
        findsOneWidget,
      );
      s.dispose();
    });
  });

  group('actions', () {
    testWidgets('Copy puts the text on the clipboard and says Copied', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['hello']);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Copy'));
      await tester.pump();
      await tester.pump();

      expect(written, ['hello']);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a failed Copy says Couldn\'t copy', (tester) async {
      final failing = HistoryService(
        store: store,
        source: source,
        log: const NullErrorLog(),
        writeClipboard: (_) async => throw Exception('no'),
      )..start();
      await show(tester, failing);
      copyTexts(['hello']);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Copy'));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't copy. Try again."), findsOneWidget);
      failing.dispose();
    });

    testWidgets('Delete removes the item; the toast has Undo for 5 seconds', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
      await tester.pump();
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
      expect(service.items.length, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Deleted'),
        findsOneWidget,
        reason: 'still there at 1 s',
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Deleted'), findsNothing);
    });

    testWidgets('Undo puts the item back where it was', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['a', 'b', 'c']);
      await tester.pumpAndSettle();
      final middle = service.items[1].id;

      await tester.tap(find.bySemanticsIdentifier('history-delete-$middle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(service.items.map((i) => i.preview), ['c', 'b', 'a']);
      handle.dispose();
    });

    testWidgets('Clear history asks first; Cancel keeps everything', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();

      expect(find.text('Clear all history?'), findsOneWidget);
      expect(
        find.text('This deletes all 2 items. Snippets are not affected.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.items.length, 2);
    });

    testWidgets('Clear history clears and shows the empty state', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();

      expect(service.items, isEmpty);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets(
      'Cancel is the default choice and not styled as the danger action',
      (tester) async {
        await show(tester);
        copyTexts(['a']);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear history'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
        final cancel = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Cancel'),
        );
        expect(cancel.autofocus, isTrue);
      },
    );
  });

  group('Keep N items field', () {
    // The Keep field is in the Settings tab since M1.7 (D1 A).
    Future<void> show(WidgetTester tester, [HistoryService? s]) async {
      await tester.pumpWidget(app(s ?? service, settings: true));
      await tester.pump();
    }

    Finder field() => find.byKey(const Key('limit-field'));

    testWidgets(
      'the border uses color.border, and color.border.hover on hover',
      (tester) async {
        await show(tester);
        Color border() =>
            (tester.widget<TextField>(field()).decoration!.enabledBorder!
                    as OutlineInputBorder)
                .borderSide
                .color;
        expect(border(), KusungaTokens.light.border);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(field()));
        await tester.pump();
        expect(border(), KusungaTokens.light.borderHover);

        await mouse.moveTo(const Offset(5, 500));
        await tester.pump();
        expect(border(), KusungaTokens.light.border);
      },
    );

    testWidgets('shows the current limit', (tester) async {
      await show(tester);
      expect(tester.widget<TextField>(field()).controller!.text, '200');
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('items'), findsOneWidget);
    });

    testWidgets('out of range shows the error and saves nothing', (
      tester,
    ) async {
      await show(tester);
      for (final bad in ['5', '5001', '', '0']) {
        await tester.enterText(field(), bad);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(
          find.text('Enter a number from 10 to 5,000.'),
          findsOneWidget,
          reason: '"$bad"',
        );
        expect(service.limit, 200);
      }
    });

    testWidgets('a valid number is saved on Enter and clears the error', (
      tester,
    ) async {
      await show(tester);
      await tester.enterText(field(), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(field(), '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(service.limit, 50);
      expect(find.text('Enter a number from 10 to 5,000.'), findsNothing);
    });

    testWidgets('it is saved when the field loses focus', (tester) async {
      await show(tester);
      await tester.enterText(field(), '75');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(service.limit, 75);
    });

    testWidgets('Up and Down change the number by 10', (tester) async {
      await show(tester);
      await tester.tap(field());
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tester.widget<TextField>(field()).controller!.text, '190');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(tester.widget<TextField>(field()).controller!.text, '210');
    });

    testWidgets(
      'lowering below the count asks first; confirm deletes the oldest',
      (tester) async {
        await show(tester);
        copyTexts([for (var i = 0; i < 15; i++) 'item $i']);
        await tester.pumpAndSettle();

        await tester.enterText(field(), '10');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Keep only the newest 10 items? 5 older items will be deleted.',
          ),
          findsOneWidget,
        );
        expect(service.limit, 200, reason: 'nothing changes until confirmed');
        await tester.tap(find.widgetWithText(FilledButton, 'Delete 5 items'));
        await tester.pumpAndSettle();

        expect(service.limit, 10);
        expect(service.items.length, 10);
      },
    );

    testWidgets('Cancel keeps the limit and the items, and resets the field', (
      tester,
    ) async {
      await show(tester);
      copyTexts([for (var i = 0; i < 15; i++) 'item $i']);
      await tester.pumpAndSettle();

      await tester.enterText(field(), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(service.limit, 200);
      expect(service.items.length, 15);
      expect(tester.widget<TextField>(field()).controller!.text, '200');
    });

    testWidgets('raising or keeping above the count needs no confirm', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.enterText(field(), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(service.limit, 10);
      expect(find.textContaining('older items'), findsNothing);
    });
  });

  group('keyboard', () {
    testWidgets('Down and Up move between rows, Home and End jump', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b', 'c']);
      await tester.pumpAndSettle();

      String focusedText() {
        final ctx = FocusManager.instance.primaryFocus!.context!;
        final f = find.descendant(
          of: find.byWidget(ctx.widget),
          matching: find.byType(Text),
        );
        return tester.widget<Text>(f.first).data ?? '';
      }

      await tester.tap(find.text('c'));
      await tester.pump();
      expect(focusedText(), 'c');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedText(), 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(focusedText(), 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(focusedText(), 'c');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedText(), 'c', reason: 'stays on the first row');
    });

    testWidgets('Enter copies, Delete deletes, Ctrl+Z undoes', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('b'));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(written, ['b']);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(service.items.map((i) => i.preview), ['a']);
      expect(find.text('Deleted'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(service.items.map((i) => i.preview), ['b', 'a']);
    });

    testWidgets('Backspace deletes too, and focus moves to the next row', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b', 'c']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('c'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(service.items.map((i) => i.preview), ['b', 'a']);
      final ctx = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.descendant(
          of: find.byWidget(ctx.widget),
          matching: find.text('b'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Ctrl+Z does nothing when no delete is waiting', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('a'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(service.items.length, 1);
    });
  });

  group('keyboard: long lists and Mac shortcuts', () {
    String focusedText(WidgetTester tester) {
      final ctx = FocusManager.instance.primaryFocus!.context!;
      final f = find.descendant(
        of: find.byWidget(ctx.widget),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(f.first).data ?? '';
    }

    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey mod,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(mod);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'End reaches the last row of a long list that is not built yet',
      (tester) async {
        // QA bug 3: rows are built lazily, so the last row had no focus node to
        // focus and End did nothing.
        await show(tester);
        copyTexts([for (var i = 0; i < 200; i++) 'item $i']);
        await tester.pumpAndSettle();
        await tester.tap(find.text('item 199'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(focusedText(tester), 'item 0');
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(focusedText(tester), 'item 199');
      },
    );

    testWidgets('Cmd+Down and Cmd+Up go to the last and first row (Mac)', (
      tester,
    ) async {
      await show(tester);
      copyTexts([for (var i = 0; i < 200; i++) 'item $i']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('item 195'));
      await tester.pump();
      await chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.arrowDown,
      );
      expect(focusedText(tester), 'item 0');
      await chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.arrowUp,
      );
      expect(focusedText(tester), 'item 199');
    });

    testWidgets('Cmd+Z (Mac) undoes the last delete while the toast shows', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('b'));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(service.items.map((i) => i.preview), ['a']);
      await chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyZ);
      expect(service.items.map((i) => i.preview), ['b', 'a']);
    });
  });

  group('accessibility', () {
    testWidgets('heading, list label, row names and buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['Call me on 07700 900123', 'https://example.com/x']);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.text('History')).flagsCollection.isHeader,
        isTrue,
      );
      expect(
        find.bySemanticsLabel('Clipboard history, 2 items'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Link: https://example.com/x, copied just now'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Text: Call me on 07700 900123, copied just now'),
        findsOneWidget,
      );
      // The limit field is in the Settings tab since M1.7.
      expect(
        find.bySemanticsLabel('Number of history items to keep'),
        findsNothing,
      );

      final ids = service.items.map((i) => i.id).toList();
      for (final id in ids) {
        expect(find.bySemanticsIdentifier('history-copy-$id'), findsOneWidget);
        expect(
          find.bySemanticsIdentifier('history-delete-$id'),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('row buttons say Copy and Delete and describe their row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['hello there']);
      await tester.pumpAndSettle();

      final copy = tester.getSemantics(
        find.bySemanticsIdentifier('history-copy-${service.items.single.id}'),
      );
      expect(copy.label, 'Copy');
      expect(copy.hint, contains('hello there'));
      handle.dispose();
    });

    testWidgets('the accessible name uses only the first 500 characters', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['y' * 900]);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Text: ${'y' * 500}…, copied just now'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('targets are at least 24 px and rows at least 44 px', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['hello']);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Copy')).height,
        greaterThanOrEqualTo(24),
      );
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Delete')).width,
        greaterThanOrEqualTo(24),
      );
      final row = find.byKey(ValueKey('row-${service.items.single.id}'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    });

    testWidgets('a new row slides in, unless reduced motion is on', (
      tester,
    ) async {
      await tester.pumpWidget(app(service));
      await tester.pump();
      source.copy('animated');
      await tester.pump();
      final id = service.items.single.id;
      double opacityOf() => tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byKey(ValueKey('enter-$id')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(opacityOf(), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacityOf(), 1);

      await tester.pumpWidget(app(makeService(), disableAnimations: true));
      source.copy('still');
      await tester.pump();
      final id2 = service.items.first.id;
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: find.byKey(ValueKey('enter-$id2')),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        1,
      );
    });
  });

  group('layout', () {
    for (final (name, width, scale) in [
      ('360 px wide', 360.0, 1.0),
      ('360 px at 200% text', 360.0, 2.0),
      ('800 px wide', 800.0, 1.0),
    ]) {
      testWidgets('$name: no overflow, no sideways scroll', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final s = makeService(notices: {HistoryNotice.memoryOnly});
        await show(tester, s);
        copyTexts([
          'https://example.com/a/very/long/link/that/goes/on/and/on/forever?x=1&y=2',
          List.filled(30, 'long words here').join(' '),
        ]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        s.dispose();
      });
    }

    testWidgets('dark theme builds', (tester) async {
      await tester.pumpWidget(app(service, brightness: Brightness.dark));
      copyTexts(['hello']);
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('hello'))).extension<KusungaTokens>(),
        KusungaTokens.dark,
      );
    });
  });

  group('HistoryHost (loading)', () {
    testWidgets('no spinner under 300 ms, spinner after, then the list', (
      tester,
    ) async {
      final completer = Completer<HistoryService>();
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: HistoryHost(history: completer.future),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Opening your history…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Opening your history…'), findsOneWidget);

      completer.complete(service);
      await tester.pumpAndSettle();
      expect(find.text('Opening your history…'), findsNothing);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a fast open never flashes the spinner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: HistoryHost(history: Future.value(service)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Opening your history…'), findsNothing);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });
}
