// Independent edge cases for the VoiceOver / Narrator announcements added in
// 97a3665 (count: polite, throttled 500 ms, no repeats; row: assertive, only
// when the selection changes).
import 'package:flutter/material.dart';
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

typedef _Said = ({String message, int? assertiveness});

void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController controller;
  final said = <_Said>[];
  var now = 0;
  var started = false;

  setUp(() {
    now = 1000000;
    port = FakePickerPort();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
      clock: () => now += 10,
    );
    started = false;
    addTearDown(history.dispose);
  });

  void listen(WidgetTester tester) {
    said.clear();
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final m = message as Map<Object?, Object?>;
        if (m['type'] == 'announce') {
          final data = m['data'] as Map<Object?, Object?>;
          said.add((
            message: data['message'] as String,
            assertiveness: data['assertiveness'] as int?,
          ));
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
  }

  // The history starts inside the test body, so its timers and streams run in
  // the test's fake clock (started in setUp, the 500 ms windows run in real time).
  void copyAll(List<String> texts) {
    if (!started) {
      history.start();
      started = true;
    }
    for (final t in texts) {
      source.copy(t);
    }
  }

  Future<void> open(WidgetTester tester, {bool attach = true}) async {
    listen(tester);
    tester.view.physicalSize = const Size(560, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (!started) {
      history.start();
      started = true;
    }
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    addTearDown(controller.dispose);
    await controller.start();
    if (attach) await controller.attach(history);
    port.press();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PickerPanel(controller: controller, now: () => now),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 600));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  Iterable<String> counts() =>
      said.where((s) => s.assertiveness != 1).map((s) => s.message);
  Iterable<_Said> rows() => said.where((s) => s.assertiveness == 1);

  group('count', () {
    testWidgets('an empty history says "0 items" once and keys say nothing', (
      tester,
    ) async {
      await open(tester);
      await settle(tester);
      expect(said.map((s) => s.message), ['0 items']);
      said.clear();
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.pageUp,
      ]) {
        await key(tester, k);
      }
      expect(said, isEmpty);
    });

    testWidgets('one item says "1 item", never "1 items"', (tester) async {
      copyAll(['only']);
      await open(tester);
      await settle(tester);
      expect(said.map((s) => s.message), ['1 item']);
    });

    testWidgets('0 matches, then 1 match, then back to all items', (
      tester,
    ) async {
      copyAll(['apple', 'banana']);
      await open(tester);
      await settle(tester);
      said.clear();
      await type(tester, 'zzz');
      expect(counts(), ['0 matches']);
      await settle(tester);
      await type(tester, 'ban');
      await settle(tester);
      expect(counts(), ['0 matches', '1 match']);
      await type(tester, '');
      await settle(tester);
      expect(counts(), ['0 matches', '1 match', '2 items']);
      expect(rows(), isEmpty, reason: 'typing never speaks a row');
    });

    testWidgets('0 matches: arrow keys, Home, End and the page keys are '
        'silent', (tester) async {
      copyAll(['apple']);
      await open(tester);
      await settle(tester);
      await type(tester, 'zzz');
      await settle(tester);
      said.clear();
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.pageUp,
      ]) {
        await key(tester, k);
      }
      expect(said, isEmpty);
    });

    testWidgets('rapid typing: at most one count per 500 ms window and the '
        'last word wins', (tester) async {
      copyAll(['apple', 'avocado', 'banana', 'apricot']);
      await open(tester);
      await settle(tester);
      said.clear();
      var q = '';
      for (final c in 'avoc'.split('')) {
        q += c;
        await type(tester, q);
        await tester.pump(const Duration(milliseconds: 40));
      }
      // First change goes out at once, the rest wait for the window.
      expect(counts().length, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(counts().length, 2);
      expect(counts().last, '1 match');
      await tester.pump(const Duration(seconds: 2));
      expect(counts().length, 2, reason: 'nothing more without a change');
    });

    testWidgets('typed then undone inside one window: the old count is not '
        'repeated', (tester) async {
      copyAll(['apple', 'avocado', 'banana']);
      await open(tester);
      await settle(tester);
      said.clear();
      await type(tester, 'av'); // spoken at once, window starts
      expect(counts(), ['1 match']);
      await type(tester, 'a');
      await type(tester, 'av');
      await settle(tester);
      expect(counts(), ['1 match'], reason: 'back to "1 match", already said');
    });

    testWidgets('the list changing while open is counted politely', (
      tester,
    ) async {
      copyAll(['a', 'b']);
      await open(tester);
      await settle(tester);
      said.clear();
      source.copy('c');
      await tester.pump();
      expect(said.map((s) => s.message), ['3 items']);
      expect(
        said.single.assertiveness == null || said.single.assertiveness == 0,
        isTrue,
      );
    });

    testWidgets('history arriving after the picker opened is counted once', (
      tester,
    ) async {
      copyAll(['a', 'b']);
      await open(tester, attach: false);
      await settle(tester);
      expect(said, isEmpty, reason: 'still opening, nothing to count');
      await controller.attach(history);
      await tester.pump();
      await settle(tester);
      expect(said.map((s) => s.message), ['2 items']);
    });

    testWidgets('a burst of copies is spoken at most once per 500 ms', (
      tester,
    ) async {
      copyAll(['a']);
      await open(tester);
      await settle(tester);
      said.clear();
      for (var i = 0; i < 10; i++) {
        source.copy('n$i');
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(said.length, 1);
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(said.map((s) => s.message), ['2 items', '11 items']);
    });

    testWidgets('a copy within the first window after opening does not make '
        'two announcements at the same moment', (tester) async {
      copyAll(['a', 'b']);
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      source.copy('c');
      await tester.pump(const Duration(milliseconds: 100));
      expect(said, isEmpty, reason: 'nothing before the first window ends');
      await tester.pump(const Duration(milliseconds: 400));
      // The throttle promises at most one count per 500 ms.
      expect(counts().length, lessThanOrEqualTo(1), reason: '${counts()}');
    });
  });

  group('selected row', () {
    testWidgets('the ends of the list: Down on the last and Up on the first '
        'are silent', (tester) async {
      copyAll(['a', 'b', 'c']);
      await open(tester);
      await settle(tester);
      said.clear();
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(said, isEmpty, reason: 'already on the first row');
      await key(tester, LogicalKeyboardKey.end);
      expect(rows().length, 1);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.pageDown);
      await key(tester, LogicalKeyboardKey.end);
      expect(rows().length, 1, reason: 'on the last row nothing is new');
    });

    testWidgets('a single row never speaks a row', (tester) async {
      copyAll(['solo']);
      await open(tester);
      await settle(tester);
      said.clear();
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.pageUp,
      ]) {
        await key(tester, k);
      }
      expect(said, isEmpty);
    });

    testWidgets('Page Down and Page Up speak the row they land on, '
        'assertively, once each', (tester) async {
      copyAll([for (var i = 0; i < 40; i++) 'row $i']);
      await open(tester);
      await settle(tester);
      said.clear();
      await key(tester, LogicalKeyboardKey.pageDown);
      expect(rows().length, 1);
      final landed = rows().single.message;
      expect(landed, isNot(contains('row 39, ')), reason: 'one page, not end');
      expect(landed, contains('row '));
      await key(tester, LogicalKeyboardKey.pageUp);
      expect(rows().length, 2);
      expect(rows().last.message, '1, Text: row 39, copied just now');
      await key(tester, LogicalKeyboardKey.pageUp);
      expect(rows().length, 2, reason: 'already on the first row');
    });

    testWidgets('Page Down from near the end clamps to the last row and '
        'speaks it once', (tester) async {
      copyAll([for (var i = 0; i < 12; i++) 'row $i']);
      await open(tester);
      await settle(tester);
      for (var i = 0; i < 10; i++) {
        await key(tester, LogicalKeyboardKey.arrowDown);
      }
      said.clear();
      await key(tester, LogicalKeyboardKey.pageDown);
      expect(rows().single.message, 'Text: row 0, copied just now');
      await key(tester, LogicalKeyboardKey.pageDown);
      expect(rows().length, 1);
    });

    testWidgets('only the first nine rows carry a number', (tester) async {
      copyAll([for (var i = 0; i < 12; i++) 'row $i']);
      await open(tester);
      await settle(tester);
      said.clear();
      for (var i = 0; i < 9; i++) {
        await key(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(rows().first.message, startsWith('2, '));
      expect(rows().last.message, startsWith('Text: '), reason: 'tenth row');
    });

    testWidgets('after a search the row spoken is the filtered one', (
      tester,
    ) async {
      copyAll(['apple', 'avocado', 'banana']);
      await open(tester);
      await settle(tester);
      await type(tester, 'a');
      await settle(tester);
      said.clear();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(rows().single.message, '2, Text: avocado, copied just now');
    });

    testWidgets('a new copy while open does not speak a row by itself', (
      tester,
    ) async {
      copyAll(['a', 'b']);
      await open(tester);
      await settle(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      said.clear();
      source.copy('c');
      await tester.pump();
      expect(rows(), isEmpty);
    });

    testWidgets('the selected row is deleted while open: the selection moves '
        'to the first row and the next Down speaks the second', (tester) async {
      copyAll(['a', 'b', 'c']);
      await open(tester);
      await settle(tester);
      await key(tester, LogicalKeyboardKey.end);
      said.clear();
      history.delete(history.items.last.id);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(rows().length, 1);
      expect(rows().single.message, startsWith('2, '));
    });

    testWidgets('announcements stop after the panel is gone', (tester) async {
      copyAll(['a', 'b']);
      await open(tester);
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      said.clear();
      source.copy('c');
      await tester.pump(const Duration(seconds: 1));
      expect(said, isEmpty);
    });
  });
}
