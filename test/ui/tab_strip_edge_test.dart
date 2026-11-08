// QA-M14-1 edge tests for the shared TabStrip (main window and picker): size,
// layout, focus ring, selected marker, tap target, long labels, RTL, themes
// and keyboard. Complements test/snippets/ui/main_tabs_layout_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:kusunga/ui/tab_strip.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

void main() {
  Finder tabFinder(String id) => find.bySemanticsIdentifier(id);

  // The tab's visible box: the Container with the focus-ring border.
  Finder ringBox(String id) => find.descendant(
    of: tabFinder(id),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).borderRadius != null,
    ),
  );

  Color? ringColor(WidgetTester tester, String id) {
    final d =
        tester.widget<Container>(ringBox(id)).decoration! as BoxDecoration;
    return (d.border! as Border).top.color;
  }

  Finder underlineBox(String id) => find.descendant(
    of: tabFinder(id),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).borderRadius == null &&
          (w.decoration! as BoxDecoration).border != null,
    ),
  );

  Color underlineColor(WidgetTester tester, String id) {
    final d =
        tester.widget<Container>(underlineBox(id)).decoration! as BoxDecoration;
    return (d.border! as Border).bottom.color;
  }

  FontWeight? weight(WidgetTester tester, String id, String text) => tester
      .widget<Text>(
        find.descendant(of: tabFinder(id), matching: find.text(text)),
      )
      .style
      ?.fontWeight;

  group('TabStrip on its own', () {
    late List<FocusNode> nodes;
    late int selected;
    const ids = ['t-a', 't-b'];

    Future<void> pump(
      WidgetTester tester, {
      List<String> labels = const ['History', 'Snippets'],
      double width = 800,
      double scale = 1,
      Brightness brightness = Brightness.light,
      TextDirection dir = TextDirection.ltr,
      bool withNodes = true,
    }) async {
      selected = 0;
      nodes = [FocusNode(), FocusNode()];
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(brightness),
          home: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, set) => Align(
                  alignment: AlignmentDirectional.topStart,
                  child: TabStrip(
                    labels: labels,
                    identifiers: ids,
                    selected: selected,
                    onSelect: (i) => set(() => selected = i),
                    focusNodes: withNodes ? nodes : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final width in [560.0, 360.0]) {
      testWidgets('$width px: tabs side by side, hug label, >= 44 x 36', (
        tester,
      ) async {
        await pump(tester, width: width);
        final a = tester.getRect(tabFinder('t-a'));
        final b = tester.getRect(tabFinder('t-b'));
        expect(a.center.dy, moreOrLessEquals(b.center.dy, epsilon: 1));
        expect(a.right, lessThanOrEqualTo(b.left + 0.5));
        expect(a.width, lessThan(width / 2));
        for (final r in [a, b]) {
          expect(r.width, greaterThanOrEqualTo(44));
          expect(r.height, greaterThanOrEqualTo(36));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a one-letter label still gets a 44 x 36 target', (
      tester,
    ) async {
      await pump(tester, labels: const ['A', 'B']);
      for (final id in ids) {
        final r = tester.getRect(tabFinder(id));
        expect(r.width, greaterThanOrEqualTo(44));
        expect(r.height, greaterThanOrEqualTo(36));
      }
    });

    testWidgets('the whole 44 x 36 box taps, not just the label', (
      tester,
    ) async {
      await pump(tester, labels: const ['A', 'B']);
      final r = tester.getRect(tabFinder('t-b'));
      await tester.tapAt(r.topLeft + const Offset(2, 2));
      await tester.pump();
      expect(selected, 1);
      await tester.tapAt(
        tester.getRect(tabFinder('t-a')).bottomRight - const Offset(2, 2),
      );
      await tester.pump();
      expect(selected, 0);
    });

    testWidgets('200% text at 360 px: wraps or fits, no overflow, in bounds', (
      tester,
    ) async {
      await pump(tester, width: 360, scale: 2);
      for (final id in ids) {
        final r = tester.getRect(tabFinder(id));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        expect(r.height, greaterThanOrEqualTo(36));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('very narrow (200 px) at 200% text: wraps, no overflow', (
      tester,
    ) async {
      await pump(tester, width: 200, scale: 2);
      for (final id in ids) {
        expect(tester.getRect(tabFinder(id)).right, lessThanOrEqualTo(200));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('long labels grow the tab and wrap to a second row instead '
        'of overflowing', (tester) async {
      await pump(
        tester,
        width: 360,
        labels: const [
          'A very long history tab label indeed',
          'An even longer snippets tab label here',
        ],
      );
      final a = tester.getRect(tabFinder('t-a'));
      final b = tester.getRect(tabFinder('t-b'));
      expect(a.right, lessThanOrEqualTo(360));
      expect(b.right, lessThanOrEqualTo(360));
      expect(b.top, greaterThanOrEqualTo(a.bottom - 0.5), reason: 'wrapped');
      expect(tester.takeException(), isNull);
    });

    testWidgets('RTL: first tab on the right, in order, no overflow', (
      tester,
    ) async {
      await pump(tester, dir: TextDirection.rtl, width: 560);
      final a = tester.getRect(tabFinder('t-a'));
      final b = tester.getRect(tabFinder('t-b'));
      expect(a.center.dx, greaterThan(b.center.dx));
      expect(a.right, lessThanOrEqualTo(560));
      expect(a.center.dy, moreOrLessEquals(b.center.dy, epsilon: 1));
      expect(a.width, lessThan(280));
      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: selected tab is bold and underlined, '
          'the other is neither', (tester) async {
        await pump(tester, brightness: brightness);
        final t = KusungaTokens.of(tester.element(tabFinder('t-a')));
        expect(weight(tester, 't-a', 'History'), FontWeight.bold);
        expect(weight(tester, 't-b', 'Snippets'), FontWeight.normal);
        expect(underlineColor(tester, 't-a'), t.focus);
        expect(underlineColor(tester, 't-b'), Colors.transparent);
        await tester.tap(tabFinder('t-b'));
        await tester.pump();
        expect(weight(tester, 't-b', 'Snippets'), FontWeight.bold);
        expect(underlineColor(tester, 't-b'), t.focus);
        expect(underlineColor(tester, 't-a'), Colors.transparent);
      });

      testWidgets('${brightness.name}: focus ring is 2 px, drawn only around '
          'the focused tab and sized to the tab', (tester) async {
        await pump(tester, brightness: brightness);
        final t = KusungaTokens.of(tester.element(tabFinder('t-a')));
        expect(ringColor(tester, 't-a'), Colors.transparent);
        nodes[1].requestFocus();
        await tester.pump();
        await tester.pump();
        expect(ringColor(tester, 't-b'), t.focus);
        expect(ringColor(tester, 't-a'), Colors.transparent);
        final d =
            tester.widget<Container>(ringBox('t-b')).decoration!
                as BoxDecoration;
        expect((d.border! as Border).top.width, 2);
        // The ring is the tab's own box, not the row.
        expect(
          tester.getRect(ringBox('t-b')).size,
          tester.getRect(tabFinder('t-b')).size,
        );
        expect(tester.getRect(ringBox('t-b')).width, lessThan(200));
      });
    }

    testWidgets('selected marker does not depend on focus: shown with no '
        'focus and with focus elsewhere', (tester) async {
      await pump(tester);
      expect(nodes.any((n) => n.hasFocus), isFalse);
      expect(weight(tester, 't-a', 'History'), FontWeight.bold);
      expect(underlineColor(tester, 't-a'), isNot(Colors.transparent));
    });

    testWidgets('semantics: tab role, selected state, label', (tester) async {
      final h = tester.ensureSemantics();
      await pump(tester);
      final a = tester.getSemantics(tabFinder('t-a'));
      final b = tester.getSemantics(tabFinder('t-b'));
      expect(a.label, 'History');
      expect(a.flagsCollection.isSelected.name, 'isTrue');
      expect(b.flagsCollection.isSelected.name, isNot('isTrue'));
      h.dispose();
    });

    testWidgets('Left/Right move and wrap, focus follows, selection follows', (
      tester,
    ) async {
      await pump(tester);
      nodes[0].requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected, 1);
      expect(nodes[1].hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected, 0);
      expect(nodes[0].hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(selected, 1);
      expect(nodes[1].hasFocus, isTrue);
    });

    testWidgets('Tab key moves focus from one tab to the next', (tester) async {
      await pump(tester);
      nodes[0].requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(nodes[1].hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab, character: null);
      await tester.pump();
      expect(nodes[1].hasFocus, isFalse);
    });

    testWidgets('Enter and Space select the focused tab; other keys ignored', (
      tester,
    ) async {
      await pump(tester);
      nodes[1].requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(selected, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, 1);
      nodes[0].requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(selected, 0);
    });

    testWidgets('without focus nodes (picker mode) tabs never take focus '
        'and arrows do nothing', (tester) async {
      await pump(tester, withNodes: false);
      await tester.tap(tabFinder('t-b'));
      await tester.pump();
      expect(selected, 1);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel ?? '',
        isNot('t-b'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(selected, 1);
    });
  });

  group('Picker tabs', () {
    late FakePickerPort port;
    late HistoryService history;
    late PickerController controller;

    Future<void> show(
      WidgetTester tester, {
      required Size size,
      double scale = 1,
      Brightness brightness = Brightness.light,
      TextDirection dir = TextDirection.ltr,
    }) async {
      port = FakePickerPort();
      history = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: FakeLog(),
        snippetStore: MemorySnippetStore(),
      )..start();
      addTearDown(history.dispose);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      controller = PickerController(port: port, log: FakeLog(), isMac: true);
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(history);
      port.press();
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Directionality(textDirection: dir, child: child!),
          ),
          home: PickerPanel(controller: controller),
        ),
      );
      await tester.pump();
    }

    for (final (w, h, scale) in [
      (560.0, 420.0, 1.0),
      (360.0, 420.0, 1.0),
      (360.0, 420.0, 2.0),
    ]) {
      testWidgets('${w.toInt()} px at ${(scale * 100).toInt()}% text: tabs on '
          'one row, in bounds, >= 44 x 36', (tester) async {
        await show(tester, size: Size(w, h), scale: scale);
        final a = tester.getRect(tabFinder('picker-tab-history'));
        final b = tester.getRect(tabFinder('picker-tab-snippets'));
        expect(a.center.dy, moreOrLessEquals(b.center.dy, epsilon: 1));
        expect(a.right, lessThanOrEqualTo(b.left + 0.5));
        expect(b.right, lessThanOrEqualTo(w));
        expect(a.left, greaterThanOrEqualTo(0));
        for (final r in [a, b]) {
          expect(r.width, greaterThanOrEqualTo(44), reason: '$r');
          expect(r.height, greaterThanOrEqualTo(36), reason: '$r');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tabs hug their labels, not the panel width', (tester) async {
      await show(tester, size: const Size(560, 420));
      final a = tester.getRect(tabFinder('picker-tab-history'));
      final b = tester.getRect(tabFinder('picker-tab-snippets'));
      expect(a.width + b.width, lessThan(300));
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: selected picker tab bold + underline '
          'follows Ctrl+Tab, no focus ring (focus stays in search)', (
        tester,
      ) async {
        await show(tester, size: const Size(560, 420), brightness: brightness);
        expect(
          weight(tester, 'picker-tab-history', 'History'),
          FontWeight.bold,
        );
        expect(
          underlineColor(tester, 'picker-tab-history'),
          isNot(Colors.transparent),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          weight(tester, 'picker-tab-snippets', 'Snippets'),
          FontWeight.bold,
        );
        expect(
          underlineColor(tester, 'picker-tab-snippets'),
          isNot(Colors.transparent),
        );
        expect(
          underlineColor(tester, 'picker-tab-history'),
          Colors.transparent,
        );
        expect(ringColor(tester, 'picker-tab-snippets'), Colors.transparent);
        expect(ringColor(tester, 'picker-tab-history'), Colors.transparent);
        // Ctrl+Shift+Tab goes back.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          weight(tester, 'picker-tab-history', 'History'),
          FontWeight.bold,
        );
      });
    }

    testWidgets('RTL: picker tabs in order, in bounds', (tester) async {
      await show(tester, size: const Size(560, 420), dir: TextDirection.rtl);
      final a = tester.getRect(tabFinder('picker-tab-history'));
      final b = tester.getRect(tabFinder('picker-tab-snippets'));
      expect(a.right, lessThanOrEqualTo(560));
      expect(b.left, greaterThanOrEqualTo(0));
      expect(a.center.dy, moreOrLessEquals(b.center.dy, epsilon: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('clicking a picker tab switches without taking focus from '
        'the search field', (tester) async {
      await show(tester, size: const Size(560, 420));
      final before = FocusManager.instance.primaryFocus;
      await tester.tap(tabFinder('picker-tab-snippets'));
      await tester.pump();
      expect(
        weight(tester, 'picker-tab-snippets', 'Snippets'),
        FontWeight.bold,
      );
      expect(FocusManager.instance.primaryFocus, before);
    });
  });
}
