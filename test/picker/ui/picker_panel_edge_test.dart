// Tester probes for the picker panel: text-field keys on both platforms,
// states-matrix cells with odd content, and two Enter presses.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
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

final _rlo = String.fromCharCode(0x202E);

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

  Future<void> show(
    WidgetTester tester, {
    bool isMac = true,
    Size size = const Size(560, 420),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    controller = PickerController(port: port, log: FakeLog(), isMac: isMac);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(history);
    port.press();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PickerPanel(controller: controller, now: () => now),
      ),
    );
    await tester.pump();
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey k,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  TextEditingController text(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  group('text-field keys keep working (M1.2 lesson 2)', () {
    for (final isMac in [true, false]) {
      final os = isMac ? 'Mac' : 'Windows';
      final mod = isMac
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      final variant = TargetPlatformVariant.only(
        isMac ? TargetPlatform.macOS : TargetPlatform.windows,
      );

      testWidgets(
        '$os: Select all, then Backspace, empties the field',
        variant: variant,
        (tester) async {
          source.copy('hello');
          await show(tester, isMac: isMac);
          await tester.enterText(find.byType(TextField), 'abc');
          await tester.pump();
          await chord(tester, mod, LogicalKeyboardKey.keyA);
          expect(text(tester).selection.start, 0);
          expect(text(tester).selection.end, 3);
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(text(tester).text, '');
          expect(port.pastes, isEmpty);
        },
      );
      testWidgets(
        '$os: editing chords are left to the text field',
        variant: variant,
        (tester) async {
          // Undo cannot be driven through the test text input, so check what
          // matters: the panel's key handler does not "handle" Cmd/Ctrl + Z,
          // X, C, V, A, Backspace, Delete or the caret keys.
          source.copy('hello');
          await show(tester, isMac: isMac);
          final node = tester
              .widget<TextField>(find.byType(TextField))
              .focusNode!;
          await tester.sendKeyDownEvent(mod);
          for (final k in [
            LogicalKeyboardKey.keyZ,
            LogicalKeyboardKey.keyX,
            LogicalKeyboardKey.keyC,
            LogicalKeyboardKey.keyV,
            LogicalKeyboardKey.keyA,
            LogicalKeyboardKey.backspace,
            LogicalKeyboardKey.delete,
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.digit0,
          ]) {
            final result = node.onKeyEvent!(
              node,
              KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.keyZ,
                logicalKey: k,
                timeStamp: Duration.zero,
              ),
            );
            expect(
              result,
              KeyEventResult.ignored,
              reason: '${k.keyLabel} / $os',
            );
          }
          await tester.sendKeyUpEvent(mod);
          expect(port.pastes, isEmpty);
        },
      );

      testWidgets(
        '$os: Left, Right, Delete and Shift+Left edit the query',
        variant: variant,
        (tester) async {
          source.copy('hello');
          await show(tester, isMac: isMac);
          await tester.enterText(find.byType(TextField), 'abcd');
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(text(tester).selection.baseOffset, 2);
          await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          await tester.pump();
          expect(text(tester).text, 'abd');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          expect(text(tester).selection.baseOffset, 3);
        },
      );
    }

    testWidgets(
      'Ctrl+1 on a Mac and Cmd+1 on Windows paste nothing',
      variant: TargetPlatformVariant.all(),
      (tester) async {
        source.copy('one');
        await show(tester, isMac: true);
        await chord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.digit1,
        );
        expect(port.pastes, isEmpty);
      },
    );
  });

  group('Enter and numbers on odd states', () {
    testWidgets('no match: Enter and Cmd+1 paste nothing', (tester) async {
      source.copy('apple');
      await show(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.digit1,
      );
      expect(port.pastes, isEmpty);
      expect(controller.mode, WindowMode.picker);
    });

    testWidgets('Enter twice while native is slow pastes once', (tester) async {
      source.copy('apple');
      port.pasteGate = Completer<void>();
      await show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      expect(port.pastes.length, 1);
      port.pasteGate!.complete();
      await tester.pump();
    });

    testWidgets(
      'Enter on the row that was selected before a new copy arrived pastes that row',
      (tester) async {
        source.copy('first');
        source.copy('second');
        await show(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // "first"
        await tester.pump();
        source.copy('third'); // arrives while the user is choosing
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(port.pastes.single.text, 'first');
      },
    );

    testWidgets(
      'the selected item is deleted behind the picker: selection moves, no throw',
      (tester) async {
        source.copy('keep');
        source.copy('doomed');
        await show(tester);
        history.delete(history.items.first.id);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(port.pastes.single.text, 'keep');
      },
    );

    testWidgets('history cleared while open shows the empty state', (
      tester,
    ) async {
      source.copy('x');
      await show(tester);
      history.clear();
      await tester.pump();
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(port.pastes, isEmpty);
    });
  });

  group('states matrix: long and odd content', () {
    testWidgets(
      'a long query cut at 40 characters never ends in half an emoji',
      (tester) async {
        // BUG-P1 (low): the cut is a plain substring, so an emoji that straddles
        // character 40 leaves a lone surrogate (a replacement box) in
        // "No matches for ...".
        source.copy('something');
        await show(tester);
        await tester.enterText(find.byType(TextField), '${'a' * 39}🎉🎉');
        await tester.pump();
        final shown = tester
            .widgetList<Text>(find.textContaining('No matches for'))
            .map((t) => t.data!)
            .single;
        final units = shown.codeUnits;
        for (var i = 0; i < units.length; i++) {
          final u = units[i];
          final high = u >= 0xD800 && u <= 0xDBFF;
          final low = u >= 0xDC00 && u <= 0xDFFF;
          if (high) {
            expect(
              i + 1 < units.length &&
                  units[i + 1] >= 0xDC00 &&
                  units[i + 1] <= 0xDFFF,
              isTrue,
              reason: 'lone high surrogate at $i',
            );
          }
          if (low) {
            expect(
              i > 0 && units[i - 1] >= 0xD800 && units[i - 1] <= 0xDBFF,
              isTrue,
              reason: 'lone low surrogate at $i',
            );
          }
        }
      },
    );

    testWidgets(
      'a space typed first does not show "No matches" for a list with matches',
      (tester) async {
        // BUG-S3 seen in the panel: " " is searched as a space.
        source.copy('oneword');
        source.copy('another');
        await show(tester);
        await tester.enterText(find.byType(TextField), ' ');
        await tester.pump();
        expect(find.textContaining('No matches'), findsNothing);
      },
    );

    testWidgets('a family emoji shows as the emoji, not as [U+200D] codes', (
      tester,
    ) async {
      // BUG-V1: visibleText turns the zero-width joiner inside emoji
      // sequences into "[U+200D]".
      source.copy('family 👨‍👩‍👧 photo');
      await show(tester);
      final shown = tester
          .widgetList<Text>(find.byKey(const ValueKey('picker-row-text')))
          .map((t) => t.textSpan!.toPlainText())
          .single;
      expect(shown, isNot(contains('[U+200D]')));
    });

    testWidgets(
      'a rainbow flag (ZWJ + variation selector) shows as one emoji',
      (tester) async {
        source.copy('pride \u{1F3F3}️‍\u{1F308}');
        await show(tester);
        final shown = tester
            .widgetList<Text>(find.byKey(const ValueKey('picker-row-text')))
            .map((t) => t.textSpan!.toPlainText())
            .single;
        expect(shown, isNot(contains('[U+')));
      },
    );

    testWidgets(
      'text with a NUL and a bidi override is shown as codes, one line',
      (tester) async {
        source.copy('pay\u0000to${_rlo}1234');
        await show(tester);
        final shown = tester
            .widgetList<Text>(find.byKey(const ValueKey('picker-row-text')))
            .map((t) => t.textSpan!.toPlainText())
            .single;
        expect(shown.codeUnits, isNot(contains(0)));
        expect(shown.codeUnits, isNot(contains(0x202E)));
        expect(shown, contains('[U+202E]'));
      },
    );
  });

  group('small and large settings', () {
    for (final dark in [false, true]) {
      testWidgets(
        'no-match and loading states at 360 x 240, 200% text, ${dark ? 'dark' : 'light'}',
        (tester) async {
          source.copy('apple');
          await show(
            tester,
            size: const Size(360, 240),
            textScale: 2,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
          await tester.enterText(find.byType(TextField), 'q' * 100);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('No matches for'), findsOneWidget);
        },
      );
    }

    testWidgets('empty history at 360 x 240 and 200% text has no overflow', (
      tester,
    ) async {
      await show(tester, size: const Size(360, 240), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets(
      'empty history, nothing to paste, every control still has a name',
      (tester) async {
        await show(tester);
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );
  });
}
