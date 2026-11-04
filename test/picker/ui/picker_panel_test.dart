import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../fake_picker_port.dart';

void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController controller;
  var now = 0;

  setUp(() {
    now = 1000000;
    port = FakePickerPort();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
      clock: () => now += 10,
    )..start();
    addTearDown(history.dispose);
  });

  void copyAll(List<String> texts) {
    for (final t in texts) {
      source.copy(t);
    }
  }

  Future<void> show(
    WidgetTester tester, {
    bool isMac = true,
    bool attach = true,
    Size size = const Size(560, 420),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    bool disableAnimations = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    controller = PickerController(port: port, log: FakeLog(), isMac: isMac);
    addTearDown(controller.dispose);
    await controller.start();
    if (attach) await controller.attach(history);
    port.press();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: PickerPanel(controller: controller, now: () => now),
      ),
    );
    await tester.pump();
  }

  Finder row(int id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == 'picker-row-$id',
  );

  /// The text of every row, top to bottom.
  List<String> rowTexts(WidgetTester tester) => [
    for (final e in find.byKey(const ValueKey('picker-row-text')).evaluate())
      (e.widget as Text).textSpan!.toPlainText(),
  ];

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  group('opening', () {
    testWidgets('search is focused, first row selected, newest first', (
      tester,
    ) async {
      copyAll(['oldest', 'middle', 'newest']);
      await show(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      expect(rowTexts(tester), ['newest', 'middle', 'oldest']);
      expect(find.text('Search history…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('picker-selected-marker')),
        findsOneWidget,
      );
    });

    testWidgets('rows 1 to 9 are numbered, later rows are not', (tester) async {
      copyAll([for (var i = 0; i < 12; i++) 'item $i']);
      tester.view.physicalSize = const Size(560, 800);
      await show(tester, size: const Size(560, 800));
      for (var n = 1; n <= 9; n++) {
        expect(find.text('$n'), findsOneWidget, reason: 'number $n');
      }
      expect(find.text('10'), findsNothing);
    });

    testWidgets('the footer shows the hints and the count (Mac)', (
      tester,
    ) async {
      copyAll(['a', 'b']);
      await show(tester);
      expect(find.text('↵ Paste'), findsOneWidget);
      expect(find.text('⌘1–9 Quick paste'), findsOneWidget);
      expect(find.text('esc Close'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
    });

    testWidgets('the footer says Ctrl on Windows', (tester) async {
      copyAll(['a']);
      await show(tester, isMac: false);
      expect(find.text('Ctrl+1–9 Quick paste'), findsOneWidget);
      expect(find.text('1 items'), findsNothing);
      expect(find.text('1 item'), findsOneWidget);
    });

    testWidgets('empty history shows the empty state, Enter does nothing', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.text('Copy some text in any app and it will appear here.'),
        findsOneWidget,
      );
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes, isEmpty);
    });

    testWidgets('while the history opens: one loading row, typing works', (
      tester,
    ) async {
      await show(tester, attach: false);
      expect(find.text('Opening your history…'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'abc');
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes, isEmpty);
      expect(find.text('Opening your history…'), findsOneWidget);

      copyAll(['abcdef', 'xyz']);
      await controller.attach(history);
      await tester.pump();
      expect(find.text('Opening your history…'), findsNothing);
      expect(rowTexts(tester), ['abcdef']);
    });

    testWidgets('a 100 ms fade unless reduce motion is on', (tester) async {
      copyAll(['a']);
      await show(tester, disableAnimations: false);
      FadeTransition fade() => tester.widget<FadeTransition>(
        find.byKey(const ValueKey('picker-fade')),
      );
      expect(fade().opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 120));
      expect(fade().opacity.value, 1);
    });

    testWidgets('no fade with reduce motion', (tester) async {
      copyAll(['a']);
      await show(tester, disableAnimations: true);
      expect(find.byKey(const ValueKey('picker-fade')), findsNothing);
    });
  });

  group('typing filters the list', () {
    testWidgets('as you type, over the previews, ignoring case', (
      tester,
    ) async {
      copyAll([
        'Call me on 07700 900123',
        'Meeting notes',
        'https://example.com',
      ]);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'ME');
      await tester.pump();
      expect(rowTexts(tester), ['Meeting notes', 'Call me on 07700 900123']);
      expect(find.text('2 matches'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'meet');
      await tester.pump();
      expect(rowTexts(tester), ['Meeting notes']);
      expect(find.text('1 match'), findsOneWidget);
    });

    testWidgets('no match: the no-match state with the query', (tester) async {
      copyAll(['abc']);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No matches for "zzz"'), findsOneWidget);
      expect(find.text('Try fewer letters.'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes, isEmpty);
    });

    testWidgets('a long query is shown cut to 40 characters', (tester) async {
      copyAll(['abc']);
      await show(tester);
      final q = 'q' * 60;
      await tester.enterText(find.byType(TextField), q);
      await tester.pump();
      expect(find.text('No matches for "${'q' * 40}…"'), findsOneWidget);
    });

    testWidgets('matches are bold and underlined, not only coloured', (
      tester,
    ) async {
      copyAll(['Banana bandana']);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'ban');
      await tester.pump();
      final rich = tester.widget<Text>(
        find.byKey(const ValueKey('picker-row-text')),
      );
      final spans = <TextSpan>[];
      rich.textSpan!.visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      final marked = [
        for (final s in spans)
          if (s.style?.decoration == TextDecoration.underline &&
              s.style?.fontWeight == FontWeight.bold)
            s.text,
      ];
      expect(marked, ['Ban', 'ban']);
    });

    testWidgets('the selection goes back to the first row after typing', (
      tester,
    ) async {
      copyAll(['ab 1', 'ab 2', 'ab 3']);
      await show(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes.single.text, 'ab 3');
    });

    testWidgets('a new copy while open joins the list; selection stays put', (
      tester,
    ) async {
      copyAll(['one', 'two']);
      await show(tester);
      await key(tester, LogicalKeyboardKey.arrowDown); // on "one"
      copyAll(['three']);
      await tester.pump();
      expect(rowTexts(tester), ['three', 'two', 'one']);
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes.single.text, 'one');
    });
  });

  group('keyboard', () {
    testWidgets('Up and Down move the selection and stop at the ends', (
      tester,
    ) async {
      copyAll(['a', 'b', 'c']);
      await show(tester);
      Future<String> pasteSelected() async {
        port.pastes.clear();
        port.press(); // reopen state for the next paste
        await key(tester, LogicalKeyboardKey.enter);
        return port.pastes.single.text;
      }

      await key(tester, LogicalKeyboardKey.arrowUp); // at the top already
      expect(await pasteSelected(), 'c');
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown); // past the end
      expect(await pasteSelected(), 'a');
    });

    testWidgets('Home, End, Page Up and Page Down', (tester) async {
      copyAll([for (var i = 0; i < 30; i++) 'item $i']);
      await show(tester);
      Future<String> pasteSelected() async {
        port.pastes.clear();
        port.press();
        await key(tester, LogicalKeyboardKey.enter);
        return port.pastes.single.text;
      }

      await key(tester, LogicalKeyboardKey.end);
      expect(await pasteSelected(), 'item 0');
      await key(tester, LogicalKeyboardKey.home);
      expect(await pasteSelected(), 'item 29');
      await key(tester, LogicalKeyboardKey.pageDown);
      final afterPageDown = await pasteSelected();
      expect(afterPageDown, isNot('item 29'));
      await key(tester, LogicalKeyboardKey.pageUp);
      expect(await pasteSelected(), 'item 29');
    });

    testWidgets('holding Down keeps moving', (tester) async {
      copyAll(['a', 'b', 'c']);
      await show(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes.single.text, 'a');
    });

    testWidgets('the selected row scrolls into view', (tester) async {
      copyAll([for (var i = 0; i < 100; i++) 'item $i']);
      await show(tester);
      await key(tester, LogicalKeyboardKey.end);
      expect(find.text('item 0'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.home);
      expect(find.text('item 99'), findsOneWidget);
    });

    testWidgets('Enter pastes the selected item, whole', (tester) async {
      final long = 'w' * 3000;
      copyAll(['short', long]);
      await show(tester);
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes.single.text, long);
      expect(port.pastes.single.post, isTrue);
      expect(controller.mode, WindowMode.manage);
    });

    testWidgets('the numpad Enter pastes too', (tester) async {
      copyAll(['a']);
      await show(tester);
      await key(tester, LogicalKeyboardKey.numpadEnter);
      expect(port.pastes.single.text, 'a');
    });

    testWidgets('Cmd+2 pastes the second row (Mac)', (tester) async {
      copyAll(['a', 'b', 'c']);
      await show(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(port.pastes.single.text, 'b');
    });

    testWidgets('Ctrl+1 pastes the first row (Windows)', (tester) async {
      copyAll(['a', 'b']);
      await show(tester, isMac: false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(port.pastes.single.text, 'b');
    });

    testWidgets('AltGr+7 and AltGr+8 type { and [ instead of pasting (K2)', (
      tester,
    ) async {
      copyAll([for (var i = 0; i < 9; i++) 'row $i']);
      await show(tester, isMac: false);
      // On Windows AltGr is Ctrl+Alt.
      for (final digit in [
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
        await tester.sendKeyEvent(digit);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }
      expect(port.pastes, isEmpty);
    });

    testWidgets('Cmd+Shift+2 and Ctrl+Cmd+2 are not quick paste (Mac)', (
      tester,
    ) async {
      copyAll(['a', 'b', 'c']);
      await show(tester);
      for (final extra in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(extra);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.sendKeyUpEvent(extra);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }
      expect(port.pastes, isEmpty);
    });

    testWidgets('Cmd+9 with fewer rows pastes nothing', (tester) async {
      copyAll(['a', 'b']);
      await show(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(port.pastes, isEmpty);
    });

    testWidgets('Cmd+number counts the filtered rows', (tester) async {
      copyAll(['apple', 'banana', 'avocado']);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'av');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(port.pastes.single.text, 'avocado');
    });

    testWidgets('a plain digit is typed into the search field', (tester) async {
      copyAll(['abc']);
      await show(tester);
      await key(tester, LogicalKeyboardKey.digit2);
      expect(port.pastes, isEmpty);
      // The key is left to the text field (it is not handled by the panel).
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      expect(find.text('No matches for "2"'), findsOneWidget);
    });

    testWidgets('Esc closes the picker', (tester) async {
      copyAll(['a']);
      await show(tester);
      await key(tester, LogicalKeyboardKey.escape);
      expect(port.calls, contains('close'));
      expect(controller.mode, WindowMode.manage);
    });

    testWidgets('Tab and Shift+Tab stay inside the panel', (tester) async {
      copyAll(['a', 'b']);
      await show(tester);
      final node = tester.widget<TextField>(find.byType(TextField)).focusNode!;
      await key(tester, LogicalKeyboardKey.tab);
      expect(node.hasPrimaryFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
    });

    testWidgets(
      'text editing keys still work in the search field',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        // M1.2 lesson 2: a screen-wide shortcut swallowed text-field keys.
        copyAll(['hello', 'world']);
        await show(tester);
        final field = tester.widget<TextField>(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'hel');
        await tester.pump();
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          field.controller!.selection.baseOffset,
          2,
          reason: 'caret moved',
        );
        await key(tester, LogicalKeyboardKey.backspace);
        expect(field.controller!.text, 'hl');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(field.controller!.selection.start, 0);
        expect(field.controller!.selection.end, 2, reason: 'Cmd+A selects all');
        expect(port.pastes, isEmpty);
      },
    );
  });

  group('focus (B1)', () {
    testWidgets('the search field takes the focus back when the app comes to '
        'the front', (tester) async {
      copyAll(['a']);
      await show(tester);
      final node = tester.widget<TextField>(find.byType(TextField)).focusNode!;
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(node.hasPrimaryFocus, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
    });

    testWidgets('it asks for the focus after the first frame too', (
      tester,
    ) async {
      copyAll(['a']);
      await show(tester);
      final node = tester.widget<TextField>(find.byType(TextField)).focusNode!;
      expect(node.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('spoken announcements for VoiceOver and Narrator', () {
    // What reaches the platform's speech: Flutter's live regions are not always
    // spoken on macOS, so the picker also sends explicit announcements.
    final spoken = <({String message, int? assertiveness})>[];

    void listen(WidgetTester tester) {
      spoken.clear();
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final m = message as Map<Object?, Object?>;
            if (m['type'] == 'announce') {
              final data = m['data'] as Map<Object?, Object?>;
              spoken.add((
                message: data['message'] as String,
                assertiveness: data['assertiveness'] as int?,
              ));
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
    }

    testWidgets('the number of items is spoken when the picker opens', (
      tester,
    ) async {
      listen(tester);
      copyAll(['a', 'b', 'c']);
      await show(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(spoken.map((e) => e.message), contains('3 items'));
    });

    testWidgets('moving the selection speaks the new row, once, assertively', (
      tester,
    ) async {
      listen(tester);
      copyAll(['alpha', 'beta']);
      await show(tester);
      await tester.pump(const Duration(milliseconds: 600));
      spoken.clear();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(spoken.length, 1);
      expect(spoken.single.message, '2, Text: alpha, copied just now');
      expect(spoken.single.assertiveness, 1);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(spoken.last.message, '1, Text: beta, copied just now');
    });

    testWidgets('Home, End and the page keys speak the row too', (
      tester,
    ) async {
      listen(tester);
      copyAll([for (var i = 0; i < 30; i++) 'row $i']);
      await show(tester);
      await tester.pump(const Duration(milliseconds: 600));
      spoken.clear();
      await key(tester, LogicalKeyboardKey.end);
      expect(spoken.single.message, 'Text: row 0, copied just now');
      await key(tester, LogicalKeyboardKey.home);
      expect(spoken.last.message, '1, Text: row 29, copied just now');
    });

    testWidgets('at the end of the list nothing new is spoken', (tester) async {
      listen(tester);
      copyAll(['a', 'b']);
      await show(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await key(tester, LogicalKeyboardKey.end);
      spoken.clear();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(spoken, isEmpty, reason: 'same row again');
    });

    testWidgets('a changed match count is spoken politely, at most every '
        '500 ms', (tester) async {
      listen(tester);
      copyAll(['apple', 'avocado', 'banana']);
      await show(tester);
      await tester.pump(const Duration(milliseconds: 600));
      spoken.clear();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'av');
      await tester.pump(const Duration(milliseconds: 100));
      expect(spoken.map((e) => e.message), ['3 matches']);
      await tester.pump(const Duration(milliseconds: 600));
      expect(spoken.map((e) => e.message), ['3 matches', '1 match']);
      expect(
        spoken.every((e) => e.assertiveness == null || e.assertiveness == 0),
        isTrue,
      );
    });

    testWidgets('the same count is not spoken twice', (tester) async {
      listen(tester);
      copyAll(['apple', 'avocado']);
      await show(tester);
      await tester.pump(const Duration(milliseconds: 600));
      spoken.clear();
      await tester.enterText(find.byType(TextField), 'ap');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), 'app');
      await tester.pump(const Duration(milliseconds: 600));
      expect(spoken.map((e) => e.message), ['1 match']);
    });

    testWidgets('Up, Down, Home and End never move the caret in the field', (
      tester,
    ) async {
      copyAll(['abcdef', 'abcxyz']);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      final caret = field.controller!.selection;
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ]) {
        await key(tester, k);
        expect(field.controller!.selection, caret, reason: '$k');
      }
    });
  });

  group('search field borders', () {
    testWidgets('1 px border, darker on hover, 2 px focus ring', (
      tester,
    ) async {
      copyAll(['a']);
      await show(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      final border = field.decoration!.border! as WidgetStateInputBorder;
      final t = KusungaTokens.light;
      expect(border.resolve({}).borderSide.color, t.border);
      expect(border.resolve({}).borderSide.width, 1);
      expect(
        border.resolve({WidgetState.hovered}).borderSide.color,
        t.borderHover,
      );
      final focused = border.resolve({WidgetState.focused}).borderSide;
      expect(focused.color, t.focus);
      expect(focused.width, 2);
    });
  });

  group('search field for screen readers (A1)', () {
    testWidgets('one text-field node: named, focused, with the typed value', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      copyAll(['hello']);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'hel');
      await tester.pump();
      final fields = <SemanticsData>[];
      void walk(SemanticsNode n) {
        final d = n.getSemanticsData();
        if (d.flagsCollection.isTextField) fields.add(d);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      // ignore: deprecated_member_use
      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      expect(fields.length, 1);
      final d = fields.single;
      expect(d.label, contains('Search history'));
      expect(d.value, 'hel');
      expect(d.flagsCollection.isFocused, Tristate.isTrue);
      expect(d.hasAction(SemanticsAction.setText), isTrue);
      expect(d.hasAction(SemanticsAction.setSelection), isTrue);
      handle.dispose();
    });
  });

  group('mouse', () {
    testWidgets('a click on a row pastes it', (tester) async {
      copyAll(['first', 'second']);
      await show(tester);
      await tester.tap(find.text('first'));
      await tester.pump();
      expect(port.pastes.single.text, 'first');
    });

    testWidgets('hovering a row does not move the selection', (tester) async {
      copyAll(['a', 'b']);
      await show(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.text('a')));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      expect(port.pastes.single.text, 'b');
    });
  });

  group('screen reader', () {
    testWidgets('the panel is a named dialog; the field and rows have names', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      copyAll(['Call me on 07700 900123']);
      await show(tester);
      expect(find.bySemanticsLabel('Kusunga picker'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Search history')), findsWidgets);
      final id = history.items.single.id;
      final node = tester.getSemantics(row(id));
      expect(node.label, '1, Text: Call me on 07700 900123, copied just now');
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('the selection and the count are live regions', (tester) async {
      final handle = tester.ensureSemantics();
      copyAll(['a', 'b']);
      await show(tester);
      expect(find.bySemanticsLabel('2 items'), findsWidgets);
      final live = tester.getSemantics(
        find.byKey(const ValueKey('picker-selection-announcement')),
      );
      expect(live.flagsCollection.isLiveRegion, isTrue);
      expect(live.label, '1, Text: b, copied just now');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('picker-selection-announcement')),
            )
            .label,
        '2, Text: a, copied just now',
      );
      handle.dispose();
    });

    testWidgets('the count is announced at most every 500 ms', (tester) async {
      final handle = tester.ensureSemantics();
      copyAll(['apple', 'avocado', 'banana']);
      await show(tester);
      Finder count(String t) => find.bySemanticsLabel(t);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'av');
      await tester.pump(const Duration(milliseconds: 100));
      // The visible footer is current; the spoken text waits for the throttle.
      expect(count('3 items'), findsWidgets);
      await tester.pump(const Duration(milliseconds: 600));
      expect(count('1 match'), findsWidgets);
      handle.dispose();
    });

    testWidgets('every control has a name (guidelines)', (tester) async {
      final handle = tester.ensureSemantics();
      copyAll(['Call me on 07700 900123', 'https://example.com']);
      await show(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    for (final b in Brightness.values) {
      testWidgets('contrast with a selected row, ${b.name}', (tester) async {
        final handle = tester.ensureSemantics();
        copyAll(['Call me on 07700 900123', 'Meeting notes']);
        await show(tester, brightness: b);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('rows are at least 32 px high', (tester) async {
      copyAll(['a']);
      await show(tester);
      final size = tester.getSize(
        find.byKey(const ValueKey('picker-row-box')).first,
      );
      expect(size.height, greaterThanOrEqualTo(32));
    });
  });

  group('sizes', () {
    testWidgets('the smallest picker (360 x 240) has no overflow', (
      tester,
    ) async {
      copyAll([for (var i = 0; i < 20; i++) 'row $i with some longer text']);
      await show(tester, size: const Size(360, 240));
      expect(tester.takeException(), isNull);
    });

    testWidgets('200% text at the smallest size has no overflow', (
      tester,
    ) async {
      copyAll([for (var i = 0; i < 20; i++) 'row $i with some longer text']);
      await show(tester, size: const Size(360, 240), textScale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the footer hints wrap below 480 px', (tester) async {
      copyAll(['a']);
      await show(tester, size: const Size(420, 420));
      expect(tester.takeException(), isNull);
      expect(find.text('esc Close'), findsOneWidget);
    });

    testWidgets('very long and odd texts stay on one line each', (
      tester,
    ) async {
      copyAll([
        'x' * 2000,
        'line one\nline two\n\nline three',
        'a\u202Eb',
        '\u{1F600}' * 500,
      ]);
      await show(tester);
      expect(tester.takeException(), isNull);
      for (final e
          in find.byKey(const ValueKey('picker-row-text')).evaluate()) {
        final rp = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byWidget(e.widget),
            matching: find.byType(RichText),
          ),
        );
        expect(rp.maxLines, 1);
        expect(rp.size.height, lessThan(40));
      }
    });

    testWidgets('5,000 items build lazily', (tester) async {
      history.setLimit(5000);
      for (var i = 0; i < 5000; i++) {
        source.copy('item number $i');
      }
      await show(tester);
      expect(tester.takeException(), isNull);
      controller.dispose(); // stops the background indexing
      expect(
        find.byKey(const ValueKey('picker-row-text')).evaluate().length,
        lessThan(30),
      );
      await tester.enterText(find.byType(TextField), 'number 4999');
      await tester.pump();
      expect(find.text('1 match'), findsOneWidget);
    });
  });
}
