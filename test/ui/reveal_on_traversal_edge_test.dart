// M1.9a round 5 (tester): `revealOnTraversal` is shared by the main window and
// Settings. B2 made it reveal the 2 px focus ring, not only the control. These
// tests drive it on its own: both edges, both directions, both axes, a view
// smaller than the control, bouncing physics, and a focus node that is not a
// box.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/ui/focus_order.dart';

/// The focus ring outside a control (`KusungaTokens.themeData`), in px.
const _ring = 2.0;

/// A real app around the content, so Tab and Shift+Tab are bound.
Widget _app(Widget child) => MaterialApp(home: Material(child: child));

class FocusRig {
  FocusRig(int n)
    : nodes = [for (var i = 0; i < n; i++) FocusNode(debugLabel: '$i')];
  final List<FocusNode> nodes;
  void dispose() {
    for (final n in nodes) {
      n.dispose();
    }
  }
}

Future<void> tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pump();
}

Rect viewOf(WidgetTester tester) =>
    tester.getRect(find.byType(SingleChildScrollView));

Rect ringOfFocus() => FocusManager.instance.primaryFocus!.rect.inflate(_ring);

Future<FocusRig> pump(
  WidgetTester tester, {
  int count = 12,
  double view = 200,
  double box = 40,
  Axis axis = Axis.vertical,
  ScrollPhysics? physics,
  double edgePadding = 8,
}) async {
  final rig = FocusRig(count);
  addTearDown(rig.dispose);
  tester.view.physicalSize = const Size(600, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final items = [
    for (var i = 0; i < count; i++)
      Padding(
        padding: axis == Axis.vertical
            ? const EdgeInsets.only(bottom: 10)
            : const EdgeInsets.only(right: 10),
        child: Focus(
          focusNode: rig.nodes[i],
          child: SizedBox(width: box, height: box),
        ),
      ),
  ];
  await tester.pumpWidget(
    _app(
      Align(
        alignment: Alignment.topLeft,
        child: FocusTraversalGroup(
          policy: revealingReadingOrder(),
          child: SizedBox(
            width: axis == Axis.vertical ? 100 : view,
            height: axis == Axis.vertical ? view : 100,
            child: SingleChildScrollView(
              scrollDirection: axis,
              physics: physics,
              padding: EdgeInsets.all(edgePadding),
              child: axis == Axis.vertical
                  ? Column(children: items)
                  : Row(children: items),
            ),
          ),
        ),
      ),
    ),
  );
  // Tab from nothing goes where the policy likes; start on the first control.
  rig.nodes.first.requestFocus();
  await tester.pump();
  return rig;
}

bool within(Rect inner, Rect outer) =>
    inner.top >= outer.top - 0.01 &&
    inner.bottom <= outer.bottom + 0.01 &&
    inner.left >= outer.left - 0.01 &&
    inner.right <= outer.right + 0.01;

void main() {
  group('revealOnTraversal shows the whole focus ring', () {
    testWidgets('Tab down through every control: ring in view each time', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 1; i < 12; i++) {
        await tab(tester);
        expect(
          within(ringOfFocus(), viewOf(tester)),
          isTrue,
          reason: 'step $i: ${ringOfFocus()} in ${viewOf(tester)}',
        );
      }
    });

    testWidgets('Shift+Tab up through every control: ring in view each time', (
      tester,
    ) async {
      final rig = await pump(tester);
      rig.nodes.last.requestFocus();
      await tester.pump();
      for (var i = 0; i < 11; i++) {
        await tab(tester, shift: true);
        expect(
          within(ringOfFocus(), viewOf(tester)),
          isTrue,
          reason: 'step $i: ${ringOfFocus()} in ${viewOf(tester)}',
        );
      }
      expect(FocusManager.instance.primaryFocus, rig.nodes.first);
    });

    testWidgets('across the row axis: Tab right and Shift+Tab left', (
      tester,
    ) async {
      final rig = await pump(tester, axis: Axis.horizontal);
      for (var i = 1; i < 12; i++) {
        await tab(tester);
        expect(
          within(ringOfFocus(), viewOf(tester)),
          isTrue,
          reason: 'right $i',
        );
      }
      expect(FocusManager.instance.primaryFocus, rig.nodes.last);
      for (var i = 0; i < 11; i++) {
        await tab(tester, shift: true);
        expect(
          within(ringOfFocus(), viewOf(tester)),
          isTrue,
          reason: 'left $i',
        );
      }
    });

    testWidgets('the first and last control at the very ends of the content '
        'do not scroll past the ends (bouncing physics, as on macOS)', (
      tester,
    ) async {
      await pump(tester, physics: const BouncingScrollPhysics());
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      // Shift+Tab off the first control wraps to the last, then back to the
      // first, then forward to the end again.
      for (var i = 0; i < 14; i++) {
        await tab(tester, shift: true);
        expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
      }
      for (var i = 0; i < 14; i++) {
        await tab(tester);
        expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
      }
    });

    testWidgets('a control with no padding around it at the end of the '
        'content: no error, and as much of the ring as the content allows', (
      tester,
    ) async {
      final rig = await pump(tester, edgePadding: 0);
      for (var i = 1; i < 12; i++) {
        await tab(tester);
      }
      expect(tester.takeException(), isNull);
      expect(rig.nodes.last.hasPrimaryFocus, isTrue);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      // The content ends 10 px below the last control: the ring fits.
      expect(within(ringOfFocus(), viewOf(tester)), isTrue);
      expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
    });

    testWidgets('a view smaller than the control: the focus still moves and '
        'nothing throws', (tester) async {
      final rig = await pump(tester, view: 30, box: 40, count: 4);
      for (var i = 1; i < 4; i++) {
        await tab(tester);
        expect(rig.nodes[i].hasPrimaryFocus, isTrue, reason: 'forward $i');
      }
      for (var i = 2; i >= 0; i--) {
        await tab(tester, shift: true);
        expect(rig.nodes[i].hasPrimaryFocus, isTrue, reason: 'back $i');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a view exactly as tall as the control and its ring', (
      tester,
    ) async {
      final rig = await pump(
        tester,
        view: 40 + 2 * _ring,
        edgePadding: 0,
        count: 5,
      );
      for (var i = 1; i < 5; i++) {
        await tab(tester);
        expect(rig.nodes[i].hasPrimaryFocus, isTrue);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('no scrolling ancestor: the focus moves, nothing throws', (
      tester,
    ) async {
      final a = FocusNode();
      final b = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(
        _app(
          FocusTraversalGroup(
            policy: revealingReadingOrder(),
            child: Column(
              children: [
                Focus(focusNode: a, child: const SizedBox(height: 20)),
                Focus(focusNode: b, child: const SizedBox(height: 20)),
              ],
            ),
          ),
        ),
      );
      a.requestFocus();
      await tester.pump();
      await tab(tester);
      expect(b.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a node that is not in the tree yet: it takes the request and '
        'nothing throws', (tester) async {
      final n = FocusNode();
      addTearDown(n.dispose);
      revealOnTraversal(n);
      expect(tester.takeException(), isNull);
    });
  });
}
