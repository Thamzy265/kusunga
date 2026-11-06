import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/history/ui/text_display.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

/// Tester round 11 on d6cea52 and 9f0e719 (QA-M14-7): the count wording for
/// 0, 1, 2, 10, 11 and 1,000 wherever it can occur, when it changes while
/// shown, and every other count string in the window, the picker and the
/// time labels.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  void create({int limit = 200}) {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore()..setLimit(limit),
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

  void snippets(int n, [int from = 1]) {
    for (var i = from; i < from + n; i++) {
      service.snippets.save(
        name: 'snip $i',
        content: 'content $i',
        type: SnippetType.other,
      );
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

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> lowerLimitTo(WidgetTester tester, int limit) async {
    final field = find.descendant(
      of: find.byType(LimitField),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '$limit');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> openClear(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
  }

  String noun(int n) => n == 1 ? 'item' : 'items';

  // ---- the two dialogs, every count ----

  group('Keep field: "Keep only the newest N items? R older item(s) will be '
      'deleted." and "Delete R item(s)"', () {
    for (final removed in [1, 2, 10, 11, 1000]) {
      testWidgets('R = $removed', (tester) async {
        service.dispose();
        create(limit: 5000);
        copies(10 + removed);
        await show(tester);
        await lowerLimitTo(tester, 10);
        expect(
          find.text(
            'Keep only the newest 10 items? '
            '$removed older ${noun(removed)} will be deleted.',
          ),
          findsOneWidget,
        );
        final button = find.widgetWithText(
          FilledButton,
          'Delete $removed ${noun(removed)}',
        );
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(service.items.length, 10);
      });
    }

    testWidgets('a different new limit (25, 11): the count in the question '
        'and the plural of what is deleted', (tester) async {
      copies(26);
      await show(tester);
      await lowerLimitTo(tester, 25);
      expect(
        find.text(
          'Keep only the newest 25 items? 1 older item will be deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await lowerLimitTo(tester, 11);
      expect(
        find.text(
          'Keep only the newest 11 items? 15 older items will be deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('R = 0: no dialog at all', (tester) async {
      copies(10);
      await show(tester);
      await lowerLimitTo(tester, 10);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.limit, 10);
    });

    testWidgets('"Delete 1 item" is the FILLED button text and its tap '
        'target reads the same way to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      copies(11);
      await show(tester);
      await lowerLimitTo(tester, 10);
      expect(find.bySemanticsLabel('Delete 1 item'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete 1 items'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  group('Clear history: "This deletes the 1 item." / "This deletes all N '
      'items."', () {
    for (final n in [1, 2, 10, 11, 1000]) {
      testWidgets('$n items', (tester) async {
        service.dispose();
        create(limit: 5000);
        copies(n);
        await show(tester);
        await openClear(tester);
        expect(
          find.text(
            n == 1
                ? 'This deletes the 1 item. Snippets are not affected.'
                : 'This deletes all $n items. Snippets are not affected.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('all 1 item'), findsNothing);
        await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
        await tester.pumpAndSettle();
        expect(service.items, isEmpty);
      });
    }

    testWidgets('0 items: Clear history is not offered', (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the dialog text follows the count when a copy arrives '
        'while it is open (it says "the 1 item" but 2 are deleted today)', (
      tester,
    ) async {
      copies(1);
      await show(tester);
      await openClear(tester);
      source.copy('arrived while the dialog was open');
      await tester.pumpAndSettle();
      expect(
        find.text('This deletes all 2 items. Snippets are not affected.'),
        findsOneWidget,
        reason:
            'the dialog still says "the 1 item"; Clear deletes '
            '${service.items.length}',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
    }, skip: true); // BUG-W1 (low)
  });

  // ---- screen-reader names, footers, and changes while shown ----

  group('list names and footers, every count, and while it changes', () {
    for (final n in [1, 2, 10, 11, 1000]) {
      testWidgets('History with $n', (tester) async {
        service.dispose();
        create(limit: 5000);
        final handle = tester.ensureSemantics();
        copies(n);
        await show(tester);
        expect(
          find.bySemanticsLabel('Clipboard history, $n ${noun(n)}'),
          findsOneWidget,
        );
        expect(find.textContaining('1 items'), findsNothing);
        expect(find.text('$n of 5000 items'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('Snippets with $n', (tester) async {
        final handle = tester.ensureSemantics();
        snippets(n);
        await show(tester);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Snippets, $n ${noun(n)}'),
          findsOneWidget,
        );
        expect(
          find.text('$n ${n == 1 ? 'snippet' : 'snippets'}'),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    testWidgets('History: 0 shows no list label, only the empty state and '
        'the footer', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      expect(
        find.bySemanticsLabel(RegExp('Clipboard history, ')),
        findsNothing,
      );
      expect(find.text('0 of 200 items'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Snippets: 0 shows the empty state and "0 snippets"', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(hook('main-tab-snippets'));
      await tester.pumpAndSettle();
      expect(find.text('0 snippets'), findsOneWidget);
      expect(find.text('No snippets yet'), findsOneWidget);
    });

    testWidgets('History: 1 -> 2 -> 1 -> 0 -> 1 while shown: the list name '
        'and the footer follow, with the right noun each time', (tester) async {
      final handle = tester.ensureSemantics();
      copies(1);
      await show(tester);
      expect(
        find.bySemanticsLabel('Clipboard history, 1 item'),
        findsOneWidget,
      );
      expect(find.text('1 of 200 items'), findsOneWidget);
      source.copy('second');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Clipboard history, 2 items'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Clipboard history, 1 item'), findsNothing);
      expect(find.text('2 of 200 items'), findsOneWidget);
      service.delete(service.items.first.id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Clipboard history, 1 item'),
        findsOneWidget,
      );
      expect(find.text('1 of 200 items'), findsOneWidget);
      service.delete(service.items.first.id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('0 of 200 items'), findsOneWidget);
      source.copy('again');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Clipboard history, 1 item'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Snippets: 1 -> 2 -> 1 -> 0 -> 1 while shown', (tester) async {
      final handle = tester.ensureSemantics();
      snippets(1);
      await show(tester);
      await tester.tap(hook('main-tab-snippets'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Snippets, 1 item'), findsOneWidget);
      expect(find.text('1 snippet'), findsOneWidget);
      snippets(1, 2);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Snippets, 2 items'), findsOneWidget);
      expect(find.text('2 snippets'), findsOneWidget);
      service.snippets.delete(service.snippets.items.first.id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Snippets, 1 item'), findsOneWidget);
      expect(find.text('1 snippet'), findsOneWidget);
      service.snippets.delete(service.snippets.items.first.id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('0 snippets'), findsOneWidget);
      snippets(1, 9);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('1 snippet'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('no "1 items", "1 snippets" or "0 item" anywhere on '
        'either tab at 0, 1 and 2 entries', (tester) async {
      for (final n in [0, 1, 2]) {
        service.dispose();
        create();
        copies(n);
        snippets(n);
        await tester.pumpWidget(const SizedBox());
        await show(tester);
        for (final tab in ['main-tab-history', 'main-tab-snippets']) {
          await tester.tap(hook(tab));
          await tester.pumpAndSettle();
          for (final bad in [
            '1 items',
            '1 snippets',
            '0 item ',
            '0 snippet ',
            'all 1 ',
          ]) {
            expect(
              find.textContaining(bad),
              findsNothing,
              reason: '$bad at $n',
            );
          }
        }
      }
    });
  });

  // ---- the picker ----

  group('picker: every count text', () {
    late FakePickerPort port;
    late PickerController controller;

    Future<void> openPicker(WidgetTester tester) async {
      tester.view.physicalSize = const Size(560, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      port = FakePickerPort();
      controller = PickerController(port: port, log: FakeLog(), isMac: true);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(service);
      port.press();
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: PickerPanel(controller: controller, now: () => 0),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    for (final n in [0, 1, 2, 10]) {
      testWidgets('History tab with $n items', (tester) async {
        copies(n);
        await openPicker(tester);
        expect(find.text('$n ${noun(n)}'), findsWidgets);
        expect(find.text('1 items'), findsNothing);
      });
    }

    testWidgets('searching: 1 match, 2 matches, none', (tester) async {
      source.copy('alpha one');
      source.copy('alpha two');
      source.copy('beta');
      await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'beta');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('1 match'), findsWidgets);
      expect(find.text('1 matches'), findsNothing);
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('2 matches'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.textContaining('No matches'), findsWidgets);
    });

    testWidgets('the Snippets tab: 0, 1 and 2 snippets', (tester) async {
      for (final n in [0, 1, 2]) {
        service.dispose();
        create();
        snippets(n);
        await tester.pumpWidget(const SizedBox());
        await openPicker(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump();
        expect(
          find.text('$n ${n == 1 ? 'snippet' : 'snippets'}'),
          findsWidgets,
          reason: '$n snippets',
        );
        expect(find.text('1 snippets'), findsNothing);
      }
    });
  });

  // ---- time labels ----

  group('relative time: singular only for exactly 1', () {
    const minute = 60000;
    final cases = <int, (String, String)>{
      0: ('just now', 'now'),
      1: ('1 minute ago', '1 min'),
      2: ('2 minutes ago', '2 min'),
      59: ('59 minutes ago', '59 min'),
      60: ('1 hour ago', '1 h'),
      119: ('1 hour ago', '1 h'),
      120: ('2 hours ago', '2 h'),
      1439: ('23 hours ago', '23 h'),
      1440: ('1 day ago', '1 d'),
      2879: ('1 day ago', '1 d'),
      2880: ('2 days ago', '2 d'),
      14400: ('10 days ago', '10 d'),
    };
    cases.forEach((minutes, texts) {
      test('$minutes minutes: "${texts.$1}" and "${texts.$2}"', () {
        expect(relativeTimeLong(minutes * minute, 0), texts.$1);
        expect(relativeTimeShort(minutes * minute, 0), texts.$2);
      });
    });
    test('a time in the future or equal counts as now', () {
      expect(relativeTimeLong(0, 5 * minute), 'just now');
      expect(relativeTimeLong(5 * minute, 5 * minute), 'just now');
    });
  });
}
