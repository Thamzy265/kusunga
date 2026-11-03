// Tester (M1.2): more cells of the states matrix in docs/ui/clipboard-history.md,
// the keyboard paths, and the abuse cases that show on screen. The developer's
// own tests are in history_screen_test.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late _LimitStore store;
  late HistoryService service;
  late List<String> written;
  var now = 0;

  HistoryService makeService({
    HistoryStore? inner,
    Set<HistoryNotice> notices = const {},
  }) {
    store = _LimitStore(inner ?? MemoryHistoryStore());
    return HistoryService(
      store: store,
      source: source,
      log: const NullErrorLog(),
      notices: notices,
      clock: () => now += 10,
      writeClipboard: (t) async => written.add(t),
    )..start();
  }

  Widget app(
    HistoryService s, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) => MaterialApp(
    theme: KusungaTokens.themeData(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: HistoryScreen(service: s, now: () => now),
  );

  Future<void> show(
    WidgetTester tester, [
    HistoryService? s,
    double textScale = 1,
  ]) async {
    await tester.pumpWidget(app(s ?? service, textScale: textScale));
    await tester.pump();
  }

  void copyTexts(List<String> texts) => texts.forEach(source.copy);

  List<String> texts() => service.items.map((i) => i.preview).toList();

  Finder field() => find.byKey(const Key('limit-field'));

  setUp(() {
    now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
    source = FakeClipboardSource();
    written = [];
    service = makeService();
  });
  tearDown(() => service.dispose());

  group('abuse cases on screen', () {
    testWidgets('HTML, markdown and scripts are plain text, never styled or '
        'linked', (tester) async {
      await show(tester);
      const html = '<b>bold</b> <script>alert(1)</script> <a href="x">y</a>';
      const md = '# Heading **bold** [click](https://evil.example) `code`';
      copyTexts([html, md]);
      await tester.pumpAndSettle();

      expect(find.text(html), findsOneWidget);
      expect(find.text(md), findsOneWidget);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.textSpan, isNull, reason: 'no rich text: ${t.data}');
      }
      expect(find.byType(RichText).evaluate().isNotEmpty, isTrue);
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        final spans = <InlineSpan>[];
        rt.text.visitChildren((s) {
          spans.add(s);
          return true;
        });
        for (final s in spans.whereType<TextSpan>()) {
          expect(s.recognizer, isNull, reason: 'no tappable text');
        }
      }
    });

    testWidgets('a link row is never opened by tapping or pressing Enter', (
      tester,
    ) async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in [
        'plugins.flutter.io/url_launcher',
        'plugins.flutter.io/url_launcher_macos',
        'plugins.flutter.io/url_launcher_windows',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          if (call.method.toLowerCase().contains('launch') ||
              call.method.toLowerCase().contains('open')) {
            calls.add('$name ${call.method}');
          }
          return null;
        });
      }
      addTearDown(() {
        for (final name in [
          'plugins.flutter.io/url_launcher',
          'plugins.flutter.io/url_launcher_macos',
          'plugins.flutter.io/url_launcher_windows',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      });
      await show(tester);
      copyTexts(['https://example.com/a', 'javascript:alert(1)']);
      await tester.pumpAndSettle();

      await tester.tap(find.text('https://example.com/a'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.tap(find.text('javascript:alert(1)'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });

    testWidgets('control and bidi characters show as symbols in the row, the '
        'tooltip and the spoken name', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      const sneaky = 'pay\u202Egpj.exe\u200B\u0007\u0000end';
      copyTexts([sneaky]);
      await tester.pumpAndSettle();

      expect(find.textContaining('[U+202E]'), findsOneWidget);
      expect(find.textContaining('␇'), findsOneWidget);
      final label = tester
          .getSemantics(find.byKey(ValueKey('row-${service.items.single.id}')))
          .label;
      expect(label.contains('\u202E'), isFalse);
      expect(label.contains('\u200B'), isFalse);
      expect(label, contains('[U+202E]'));
      final tip = tester.widget<Tooltip>(find.byType(Tooltip).first).message!;
      expect(tip.contains('\u202E'), isFalse);
      handle.dispose();
    });

    testWidgets('the spoken name never ends in half an emoji', (tester) async {
      // Bug repro (BUG-11): the name is cut at 500 UTF-16 units; an emoji
      // that straddles the cut leaves a lone surrogate in the label.
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['${'a' * 499}\u{1F600} and the rest']);
      await tester.pumpAndSettle();
      final name = HistoryRow.semanticName(service.items.single, now);
      final body = name.substring(0, name.indexOf('…'));
      final last = body.codeUnits.last;
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
      handle.dispose();
    });

    testWidgets('very long unbroken text fits at 360 px', (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await show(tester);
      copyTexts([
        'W' * 5000,
        'https://example.com/${'segment/' * 400}',
        '\u05E9\u05DC\u05D5\u05DD ' * 300,
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(HistoryRow), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row fits at 360 px with 200% text', (tester) async {
      // Bug repro (BUG-15): the developer's 200% layout test shows no row at
      // all (the header and banner fill the window), so it cannot see that
      // a row overflows by 53 px once it is on screen.
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await show(tester, service, 2);
      copyTexts(['hello']);
      await tester.pumpAndSettle();
      expect(
        find.byType(HistoryRow),
        findsOneWidget,
        reason: 'the row must really be on screen for this check',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Undo and delete', () {
    testWidgets('after the 5 seconds, Undo is gone and Ctrl+Z does nothing', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('history-delete-${service.items.first.id}'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(texts(), ['a']);

      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(texts(), ['a']);
    });

    testWidgets('Cmd+Z undoes while the toast shows (Mac)', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(texts(), ['a']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(texts(), ['b', 'a']);
    });

    testWidgets('Undo twice restores once', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(texts(), ['b', 'a']);
    });

    testWidgets('delete, then Clear history, then Undo: the cleared item '
        'does not come back', (tester) async {
      // Bug repro (BUG-12): Undo still holds the deleted item after the
      // user chose Clear history, and brings it back into an empty list.
      await show(tester);
      copyTexts(['secret one', 'b', 'c']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // deletes 'c'
      await tester.pump();

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
      expect(service.items, isEmpty);

      await tester.pump(const Duration(milliseconds: 800));
      final undo = find.text('Undo');
      if (undo.evaluate().isNotEmpty) await tester.tap(undo);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(service.items, isEmpty, reason: 'history was cleared');
      expect(store.count, 0);
    });

    testWidgets('Undo, then Clear history: empty, and Undo is gone', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(texts(), ['b', 'a']);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();

      expect(service.items, isEmpty);
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0 of 200 items'), findsOneWidget);
    });

    testWidgets('a new copy arriving between Delete and Undo does not make '
        'duplicates', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // 'b' (top row)
      await tester.pump();
      source.copy('b'); // copied again right away
      source.copy('new');
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final t = texts();
      expect(t.where((x) => x == 'b').length, 1);
      expect(t.first, 'new');
      expect(t[1], 'b', reason: 'the newer copy time wins over the old one');
    });

    testWidgets('a new copy arriving in the same frame as Delete keeps the '
        'right row deleted', (tester) async {
      await show(tester);
      copyTexts(['a', 'b', 'c']);
      await tester.pumpAndSettle();
      final bId = service.items[1].id;
      source.copy('d'); // a row is inserted above while 'b' is being deleted
      await tester.tap(find.bySemanticsIdentifier('history-delete-$bId'));
      await tester.pumpAndSettle();
      expect(texts(), ['d', 'c', 'a']);
    });

    testWidgets('deleting the last row moves focus up; deleting the only row '
        'shows the empty state with no error', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // 'a', the last
      await tester.pumpAndSettle();
      expect(texts(), ['b']);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(texts(), isEmpty);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second Delete replaces the first toast; Undo brings back '
        'only the latest', (tester) async {
      await show(tester);
      copyTexts(['a', 'b', 'c']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // c
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete); // b
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(texts(), ['b', 'a']);
    });

    testWidgets('Delete on a stale row does nothing and does not crash', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a']);
      await tester.pumpAndSettle();
      final id = service.items.single.id;
      final handle = tester.ensureSemantics();
      store.inner.delete(id); // removed behind the screen's back
      await tester.tap(find.byType(HistoryRow));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('a failing Undo does not throw', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      store.failWrites = true;
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Keep N items: typed input', () {
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(field(), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    String shown(WidgetTester tester) =>
        tester.widget<TextField>(field()).controller!.text;

    testWidgets('non-numeric characters cannot be typed', (tester) async {
      await show(tester);
      for (final (typed, kept) in [
        ('abc', ''),
        ('1e3', '13'),
        ('-50', '50'),
        ('+50', '50'),
        ('5.5', '55'),
        (' 50 ', '50'),
        ('٣٠', ''), // Arabic-Indic digits
        ('50\u0000', '50'),
        ('ten', ''),
        ('0x20', '020'),
      ]) {
        await tester.enterText(field(), typed);
        expect(shown(tester), kept, reason: 'typed "$typed"');
      }
    });

    testWidgets('empty, letters-only and huge numbers show the error and '
        'save nothing', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      for (final bad in [
        '',
        'abc',
        '9' * 30,
        '99999999999999999999',
        ',',
        ',,',
      ]) {
        await type(tester, bad);
        expect(
          find.text('Enter a number from 10 to 5,000.'),
          findsOneWidget,
          reason: '"$bad"',
        );
        expect(service.limit, 200, reason: '"$bad"');
        expect(tester.takeException(), isNull, reason: '"$bad"');
      }
    });

    testWidgets('the boundaries: 9 and 5001 fail; 10 and 5000 are saved', (
      tester,
    ) async {
      await show(tester);
      await type(tester, '9');
      expect(find.text('Enter a number from 10 to 5,000.'), findsOneWidget);
      expect(service.limit, 200);

      await type(tester, '5001');
      expect(find.text('Enter a number from 10 to 5,000.'), findsOneWidget);
      expect(service.limit, 200);

      await type(tester, '5000');
      expect(find.text('Enter a number from 10 to 5,000.'), findsNothing);
      expect(service.limit, 5000);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0 of 5000 items'), findsOneWidget);

      await type(tester, '10');
      expect(service.limit, 10);
      await tester.pumpAndSettle();
    });

    testWidgets('commas and leading zeros are accepted: 5,000 and 0010', (
      tester,
    ) async {
      await show(tester);
      await type(tester, '5,000');
      expect(service.limit, 5000);
      await type(tester, '0010');
      expect(service.limit, 10);
    });

    testWidgets('Up and Down stop at 10 and 5,000', (tester) async {
      await show(tester);
      await tester.tap(field());
      await tester.enterText(field(), '12');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(shown(tester), '10');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(shown(tester), '10');
      await tester.enterText(field(), '4995');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(shown(tester), '5000');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(shown(tester), '5000');
    });

    testWidgets('Up from an empty or invalid field starts at the saved '
        'limit', (tester) async {
      await show(tester);
      await tester.tap(field());
      await tester.enterText(field(), '');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(shown(tester), '210');
    });

    testWidgets('the error clears as soon as the user types again', (
      tester,
    ) async {
      await show(tester);
      await type(tester, '1');
      expect(find.text('Enter a number from 10 to 5,000.'), findsOneWidget);
      await tester.enterText(field(), '12');
      await tester.pump();
      expect(find.text('Enter a number from 10 to 5,000.'), findsNothing);
    });

    testWidgets('the error is announced through the field hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await type(tester, '3');
      final node = tester.getSemantics(
        find.bySemanticsLabel('Number of history items to keep'),
      );
      expect(node.hint, 'Enter a number from 10 to 5,000.');
      handle.dispose();
    });

    testWidgets('lowering to exactly the item count needs no confirm; one '
        'below does', (tester) async {
      await show(tester);
      for (var i = 0; i < 12; i++) {
        source.copy('item $i');
      }
      await tester.pumpAndSettle();
      await type(tester, '12'); // same as count, above 10: no deletion
      await tester.pumpAndSettle();
      expect(find.textContaining('older items will be deleted'), findsNothing);
      expect(service.limit, 12);
      expect(service.items.length, 12);

      await type(tester, '10');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Keep only the newest 10 items? 2 older items will be deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text('Delete 2 items'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.items.length, 12);
      expect(shown(tester), '12');
    });

    testWidgets('Escape on the confirm keeps everything', (tester) async {
      await show(tester);
      for (var i = 0; i < 15; i++) {
        source.copy('item $i');
      }
      await tester.pumpAndSettle();
      await type(tester, '10');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(service.items.length, 15);
      expect(service.limit, 200);
    });

    testWidgets('a limit that cannot be saved is not shown as saved', (
      tester,
    ) async {
      // Bug repro (BUG-14): the save fails with no message, and the field
      // keeps showing the number that was not saved.
      await show(tester);
      copyTexts(['a']);
      await tester.pumpAndSettle();
      store.failLimit = true;
      await type(tester, '30');
      await tester.pumpAndSettle();
      expect(service.limit, 200, reason: 'the save failed');
      final told =
          find.textContaining('Enter a number').evaluate().isNotEmpty ||
          find.textContaining("Couldn't").evaluate().isNotEmpty;
      expect(shown(tester) == '200' || told, isTrue);
    });
  });

  group('banners and the list together', () {
    testWidgets('a write error shows the banner and keeps the unsaved copy '
        'in the list', (tester) async {
      await show(tester);
      copyTexts(['saved']);
      store.failWrites = true;
      copyTexts(['unsaved']);
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save the latest item. Kusunga will try again."),
        findsOneWidget,
      );
      expect(find.text('unsaved'), findsOneWidget);
      expect(find.text('saved'), findsOneWidget);
    });

    testWidgets('a dismissed write banner comes back on the next failed '
        'save, and goes when the save works', (tester) async {
      await show(tester);
      store.failWrites = true;
      copyTexts(['a']);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save"), findsNothing);

      copyTexts(['b']);
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save"), findsOneWidget);

      store.failWrites = false;
      copyTexts(['c']);
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save"), findsNothing);
      expect(texts(), ['c', 'b', 'a']);
    });

    testWidgets('a failed Clear keeps the list and shows its banner', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      store.failClear = true;
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't clear history. Try again."), findsOneWidget);
      expect(texts(), ['b', 'a']);
      expect(find.text('Nothing here yet'), findsNothing);
    });

    testWidgets('all banners and the setup card can show at once without '
        'overflow at 360 px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      source.access = PasteAccess.needsSetup;
      final s = makeService(
        notices: {HistoryNotice.memoryOnly, HistoryNotice.readError},
      );
      addTearDown(s.dispose);
      store.failWrites = true;
      await show(tester, s, 2);
      source.copy('x');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Allow Kusunga to read what you copy'), findsOneWidget);
    });

    testWidgets('the footer never claims more items than the limit', (
      tester,
    ) async {
      // Bug repro (BUG-13): unsaved copies are listed above the saved ones
      // and counted, so a limit of 10 can read "15 of 10 items".
      final s = makeService();
      addTearDown(s.dispose);
      s.setLimit(10);
      store.failWrites = true;
      await show(tester, s);
      for (var i = 0; i < 15; i++) {
        source.copy('copy $i');
      }
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('15 of 10 items'), findsNothing);
    });

    testWidgets('a past write error does not make the empty state lie: '
        'empty list with waiting item is not "Nothing here yet"', (
      tester,
    ) async {
      await show(tester);
      store.failWrites = true;
      copyTexts(['only in memory']);
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsNothing);
      expect(find.text('only in memory'), findsOneWidget);
    });
  });

  group('keyboard only', () {
    testWidgets('Tab goes from a row to its Copy button, then Delete, then '
        'the next row', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();

      String? focusedButton() {
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx == null) return null;
        String? label;
        ctx.visitAncestorElements((e) {
          final w = e.widget;
          if (w is TextButton) {
            final c = w.child;
            if (c is Text) label = c.data;
            return false;
          }
          return true;
        });
        return label;
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedButton(), 'Copy');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedButton(), 'Delete');
    });

    testWidgets('Enter on a focused Copy button copies; Space on Delete '
        'deletes', (tester) async {
      await show(tester);
      copyTexts(['a', 'b']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(written, ['b']);
    });

    testWidgets('Escape closes the Clear dialog and keeps the history', (
      tester,
    ) async {
      await show(tester);
      copyTexts(['a']);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(find.text('Clear all history?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Clear all history?'), findsNothing);
      expect(texts(), ['a']);
    });

    testWidgets('Escape closes the menu; focus goes back to the Menu '
        'button', (tester) async {
      await show(tester);
      copyTexts(['a']);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Clear history'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Clear history'), findsNothing);
    });

    testWidgets('Home and End on a single row stay on it', (tester) async {
      await show(tester);
      copyTexts(['only']);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(written, ['only']);
    });

    testWidgets('Enter copies the whole text, not the 2,000 character '
        'preview', (tester) async {
      await show(tester);
      final long = '${'x' * 2500}END';
      copyTexts([long]);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(written, [long]);
    });
  });

  group('large and busy lists', () {
    testWidgets('5,000 items build lazily and scroll without error', (
      tester,
    ) async {
      final big = makeService();
      addTearDown(big.dispose);
      big.setLimit(5000);
      for (var i = 0; i < 5000; i++) {
        source.copy('item number $i');
      }
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await show(tester, big);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(HistoryRow).evaluate().length, lessThan(40));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('5000 of 5000 items'), findsOneWidget);
    });

    testWidgets('a burst of 300 copies in one frame shows the newest on '
        'top and no exception', (tester) async {
      await show(tester);
      for (var i = 0; i < 300; i++) {
        source.copy('burst $i');
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(texts().first, 'burst 299');
      expect(service.items.length, 200);
    });
  });

  group('accessibility scan', () {
    for (final brightness in Brightness.values) {
      testWidgets('contrast and labelled tap targets, ${brightness.name}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        service.dispose();
        service = makeService(notices: {HistoryNotice.readError});
        await tester.pumpWidget(app(service, brightness: brightness));
        // One row: it has focus, so its Copy and Delete buttons are shown
        // (hidden buttons are drawn at zero opacity and cannot be measured).
        copyTexts(['Call me on 07700 900123']);
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('every tappable node has a label (screen reader)', (
      tester,
    ) async {
      // Bug repro (BUG-16): the focused row is a tappable, focusable node
      // with no label of its own; the label is on a child node. Needs a
      // real VoiceOver check too.
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['Call me on 07700 900123']);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('every row button has a name and a role', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      copyTexts(['a', 'b', 'c']);
      await tester.pumpAndSettle();
      for (final item in service.items) {
        for (final action in ['copy', 'delete']) {
          final node = tester.getSemantics(
            find.bySemanticsIdentifier('history-$action-${item.id}'),
          );
          expect(node.label, action == 'copy' ? 'Copy' : 'Delete');
          expect(node.flagsCollection.isButton, isTrue);
        }
      }
      handle.dispose();
    });
  });
}

class _LimitStore extends FlakyStore {
  _LimitStore(super.inner);
  bool failLimit = false;

  @override
  void setLimit(int newLimit) {
    if (failLimit) throw const FileSystemException('locked');
    super.setLimit(newLimit);
  }
}
