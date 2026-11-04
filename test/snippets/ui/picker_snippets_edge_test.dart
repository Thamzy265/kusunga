// Tester probes for the picker's Snippets tab (design note, "How it works";
// UI spec, "Picker tabs" and "Picker snippet row"; PM decisions D1 and D3).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../picker/fake_picker_port.dart';
import '../../support/fakes.dart';

void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late FakeLog log;
  late HistoryService history;
  late PickerController controller;

  HistoryService makeHistory({Set<HistoryNotice> notices = const {}}) {
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      notices: notices,
      snippetStore: MemorySnippetStore(),
    )..start();
    addTearDown(h.dispose);
    return h;
  }

  setUp(() {
    port = FakePickerPort();
    source = FakeClipboardSource();
    log = FakeLog();
    history = makeHistory();
  });

  int add(String name, String content, [SnippetType? type]) => history.snippets
      .save(name: name, content: content, type: type ?? SnippetType.other)
      .id!;

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
    controller = PickerController(port: port, log: log, isMac: isMac);
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
        home: PickerPanel(controller: controller),
      ),
    );
    await tester.pump();
  }

  List<String> rowTexts(WidgetTester tester) => [
    for (final e in find.byKey(const ValueKey('picker-row-text')).evaluate())
      (e.widget as Text).textSpan!.toPlainText(),
  ];

  Future<void> toSnippets(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> quick(
    WidgetTester tester,
    LogicalKeyboardKey digit, {
    bool mac = true,
  }) async {
    final mod = mac
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(digit);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  group('D3: the picker always opens on History', () {
    testWidgets('after leaving it on Snippets, the next open is History, with '
        'a clean search', (tester) async {
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      add('My mobile', '07700 900123', SnippetType.phone);
      source.copy('in history');
      controller = PickerController(port: port, log: log, isMac: true);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(history);
      await tester.pumpWidget(
        KusungaApp(history: Future.value(history), picker: controller),
      );
      await tester.pump();
      await tester.pump();

      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.text('Search history…'), findsOneWidget);
      await toSnippets(tester);
      await tester.enterText(find.byType(TextField).last, 'mobile');
      await tester.pump();
      expect(find.text('Search snippets…'), findsOneWidget);
      // Close with Esc and open again.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.text('Search history…'), findsOneWidget);
      expect(find.text('Search snippets…'), findsNothing);
      expect(
        tester
            .widget<Semantics>(hook('picker-tab-history'))
            .properties
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<Semantics>(hook('picker-tab-snippets'))
            .properties
            .selected,
        isFalse,
      );
    });

    testWidgets('after a paste from Snippets, the next open is History', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      add('My mobile', '07700 900123', SnippetType.phone);
      controller = PickerController(port: port, log: log, isMac: true);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(history);
      await tester.pumpWidget(
        KusungaApp(history: Future.value(history), picker: controller),
      );
      await tester.pump();
      await tester.pump();
      port.press();
      await tester.pump();
      await tester.pump();
      await toSnippets(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(port.pastes.single.text, '07700 900123');
      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.text('Search history…'), findsOneWidget);
    });
  });

  group('search in the Snippets tab', () {
    testWidgets('matches the name and the content, in any case, not the type '
        'word', (tester) async {
      add('My mobile', '07700 900123', SnippetType.phone);
      add('Work email', 'will@example.com', SnippetType.email);
      add('Zoom room', 'https://zoom.us/j/12345', SnippetType.link);
      await show(tester);
      await toSnippets(tester);
      await tester.enterText(find.byType(TextField), 'WORK');
      await tester.pump();
      expect(rowTexts(tester), ['Work email — will@example.com']);
      await tester.enterText(find.byType(TextField), 'ZOOM.US');
      await tester.pump();
      expect(rowTexts(tester), ['Zoom room — https://zoom.us/j/12345']);
      await tester.enterText(find.byType(TextField), '900123');
      await tester.pump();
      expect(rowTexts(tester), ['My mobile — 07700 900123']);
      // The type word is not text of the snippet.
      await tester.enterText(find.byType(TextField), 'phone');
      await tester.pump();
      expect(rowTexts(tester), isEmpty);
      expect(find.text('0 matches'), findsOneWidget);
    });

    testWidgets('a long snippet is found by text near its start, and the '
        'whole text is what is pasted', (tester) async {
      final long = 'needle-at-start ${'y' * 5000} tail-end-marker';
      add('Long one', long);
      await show(tester);
      await toSnippets(tester);
      await tester.enterText(find.byType(TextField), 'needle-at-start');
      await tester.pump();
      expect(rowTexts(tester).length, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(port.pastes.single.text, long);
    });

    testWidgets('the query survives both switches and each tab shows its own '
        'count', (tester) async {
      add('Alpha', 'one');
      add('Beta', 'alpha again');
      source.copy('alpha in history');
      source.copy('something else');
      await show(tester);
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();
      expect(find.text('1 match'), findsOneWidget);
      await toSnippets(tester);
      expect(find.text('2 matches'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'alpha',
      );
      await toSnippets(tester); // two tabs: Ctrl+Tab goes back
      expect(find.text('1 match'), findsOneWidget);
      expect(rowTexts(tester), ['alpha in history']);
    });

    testWidgets('a name with markup, RTL marks and zero width characters is '
        'shown as text with the hidden characters made visible', (
      tester,
    ) async {
      final id = add('<b>x</b>\u{202E}rtl', 'zero\u{200B}width');
      await show(tester);
      await toSnippets(tester);
      expect(
        rowTexts(tester).single,
        '<b>x</b>[U+202E]rtl — zero[U+200B]width',
      );
      final label = tester
          .widget<Semantics>(hook('picker-snippet-row-$id'))
          .properties
          .label!;
      expect(label, '1, Other, <b>x</b>[U+202E]rtl, zero[U+200B]width');
    });
  });

  group('quick paste and Enter in the Snippets tab', () {
    testWidgets('Cmd+1 to Cmd+9 paste the 1st to 9th snippet; a digit past '
        'the last row pastes nothing', (tester) async {
      for (var i = 1; i <= 12; i++) {
        add('S$i', 'text $i');
      }
      await show(tester);
      await toSnippets(tester);
      final digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      for (var i = 0; i < 9; i++) {
        port.pastes.clear();
        port.press();
        await tester.pump();
        await tester.pump();
        await quick(tester, digits[i]);
        await tester.pump();
        expect(
          port.pastes.single.text,
          'text ${i + 1}',
          reason: 'Cmd+${i + 1}',
        );
        expect(port.pastes.single.skipHistory, isTrue);
      }
    });

    testWidgets('Cmd+N counts rows after a search; a digit beyond the shown '
        'rows pastes nothing', (tester) async {
      add('Work email', 'a@example.com');
      add('Home', '1 High Street');
      add('Work phone', '07700 900123');
      await show(tester);
      await toSnippets(tester);
      await tester.enterText(find.byType(TextField), 'work');
      await tester.pump();
      await quick(tester, LogicalKeyboardKey.digit5);
      expect(port.pastes, isEmpty);
      await quick(tester, LogicalKeyboardKey.digit2);
      expect(port.pastes.single.text, '07700 900123');
    });

    testWidgets('on Windows it is Ctrl+digit, and Cmd+digit does nothing', (
      tester,
    ) async {
      add('A', 'text a');
      await show(tester, isMac: false);
      await toSnippets(tester);
      await quick(tester, LogicalKeyboardKey.digit1, mac: true);
      expect(port.pastes, isEmpty);
      await quick(tester, LogicalKeyboardKey.digit1, mac: false);
      expect(port.pastes.single.text, 'text a');
      expect(port.pastes.single.skipHistory, isTrue);
    });

    testWidgets('pasteSource is 1 for a snippet and 0 for history, on Enter '
        'and on a number key, and each paste is logged once', (tester) async {
      add('A', 'snippet a');
      add('B', 'snippet b');
      source.copy('history one');
      await show(tester);
      log.codes.clear();
      log.details.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // history
      await tester.pump();
      expect(port.pastes.last.skipHistory, isFalse);
      port.press();
      await tester.pump();
      await tester.pump();
      await toSnippets(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // snippet
      await tester.pump();
      expect(port.pastes.last.skipHistory, isTrue);
      // The panel here is not rebuilt between opens, so it is still on
      // Snippets.
      port.press();
      await tester.pump();
      await tester.pump();
      await quick(tester, LogicalKeyboardKey.digit2); // snippet b
      expect(port.pastes.last.text, 'snippet b');
      final sources = [
        for (var i = 0; i < log.codes.length; i++)
          if (log.codes[i] == LogCode.pasteSource) log.details[i],
      ];
      expect(sources, [0, 1, 1]);
    });

    testWidgets('Enter with no match pastes nothing; a second Enter while a '
        'paste is running does not paste twice', (tester) async {
      add('A', 'text a');
      await show(tester);
      await toSnippets(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(port.pastes, isEmpty);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      port.pasteGate = Completer<void>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(port.pastes.length, 1);
      port.pasteGate!.complete();
      await tester.pump();
    });

    testWidgets('a 1 MiB snippet shows one short line and pastes all of it', (
      tester,
    ) async {
      final big = 'm' * ClipItem.maxContentLength;
      add('Big', big);
      await show(tester);
      await toSnippets(tester);
      expect(rowTexts(tester).single.length, lessThan(2100));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(port.pastes.single.text.length, ClipItem.maxContentLength);
      expect(port.pastes.single.skipHistory, isTrue);
    });

    testWidgets('a snippet that is deleted while the picker is open: the '
        'selection moves on and Enter pastes the row now shown', (
      tester,
    ) async {
      final a = add('A', 'text a');
      add('B', 'text b');
      await show(tester);
      await toSnippets(tester);
      history.snippets.delete(a);
      await tester.pump();
      expect(rowTexts(tester), ['B — text b']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(port.pastes.single.text, 'text b');
    });

    testWidgets('a snippet renamed while the picker is open is found by its '
        'new name and no longer by the old one', (tester) async {
      final a = add('Old name', 'text a');
      await show(tester);
      await toSnippets(tester);
      history.snippets.save(
        id: a,
        name: 'Fresh name',
        content: 'text a',
        type: SnippetType.other,
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'fresh');
      await tester.pump();
      expect(rowTexts(tester), ['Fresh name — text a']);
      await tester.enterText(find.byType(TextField), 'old name');
      await tester.pump();
      expect(rowTexts(tester), isEmpty);
    });

    testWidgets('memory-only: loaded snippets quick-paste, and nothing in '
        'the picker offers to edit', (tester) async {
      final store = MemorySnippetStore()
        ..insert(
          name: 'Loaded',
          content: 'kept',
          type: SnippetType.other,
          nowMs: 1,
        );
      history = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        notices: const {HistoryNotice.memoryOnly},
        snippetStore: store,
      )..start();
      addTearDown(history.dispose);
      await show(tester);
      await toSnippets(tester);
      await quick(tester, LogicalKeyboardKey.digit1);
      expect(port.pastes.single.text, 'kept');
      expect(find.text('New snippet'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });
  });

  group('picker states', () {
    testWidgets('the tab strip is a tab bar with a selected tab, and its '
        'tabs never take focus from the search field', (tester) async {
      add('A', 'a');
      await show(tester);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      await tester.tap(hook('picker-tab-snippets'));
      await tester.pump();
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      expect(
        tester
            .widget<Semantics>(hook('picker-tab-snippets'))
            .properties
            .selected,
        isTrue,
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('the Snippets tab at 200% text in the 560 x 420 panel: no '
          'overflow; contrast and labels pass ($brightness)', (tester) async {
        for (var i = 0; i < 4; i++) {
          add(
            'Snippet $i with a rather long name to cut',
            'long content ' * 20,
          );
        }
        await show(tester, textScale: 2, brightness: brightness);
        await toSnippets(tester);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }

    testWidgets('the empty Snippets tab at 200% text: no overflow', (
      tester,
    ) async {
      await show(tester, textScale: 2, size: const Size(360, 400));
      await toSnippets(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('No snippets yet'), findsOneWidget);
    });
  });
}
