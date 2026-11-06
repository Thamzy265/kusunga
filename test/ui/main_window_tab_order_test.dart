import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

/// QA-M14-5 (QA session 4, WCAG 2.4.3 / 2.4.11): with the Snippets list
/// wheel-scrolled down, Tab from the Snippets tab went to a row built off
/// screen above the list (no ring, no scroll) and Enter copied that hidden
/// row. Tab from a tab must reach the header first (New snippet), the list
/// is entered at the rows in view, and whatever Tab or Shift+Tab focuses is
/// scrolled fully into view. The History tab is checked the same way.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  final textScale = ValueNotifier<double>(1);

  setUp(() {
    textScale.value = 1;
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
    )..start();
    addTearDown(service.dispose);
  });

  void fillSnippets(int n) {
    for (var i = 1; i <= n; i++) {
      final two = i.toString().padLeft(2, '0');
      service.snippets.save(
        name: 'snip $two',
        content: 'content $two',
        type: SnippetType.other,
      );
    }
  }

  void fillHistory(int n) {
    for (var i = 1; i <= n; i++) {
      source.copy('history item $i');
    }
  }

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: textScale,
          builder: (context, scale, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
        ),
        home: HistoryHost(history: Future.value(service), initial: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> tapTab(WidgetTester tester, String id) async {
    await tester.tap(hook(id));
    await tester.pumpAndSettle();
  }

  /// A mouse-wheel scroll over the shown panel's list.
  Future<void> wheel(WidgetTester tester, Type screen, double dy) async {
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final list = find.descendant(
      of: find.byType(screen),
      matching: find.byType(CustomScrollView),
    );
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(list)));
    await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
  }

  /// The nearest Semantics identifier around the focused control.
  String? focusedHook() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? id;
    void check(Widget w) {
      if (id == null && w is Semantics && w.properties.identifier != null) {
        id = w.properties.identifier;
      }
    }

    check(context.widget);
    context.visitAncestorElements((e) {
      check(e.widget);
      return id == null;
    });
    return id;
  }

  T? focusedWidget<T extends Widget>() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    if (context.widget is T) return context.widget as T;
    return context.findAncestorWidgetOfExactType<T>();
  }

  /// Where the focused control can be seen: its list's viewport when it is
  /// in one, else the window.
  Rect seenArea(WidgetTester tester, FocusNode node) {
    final box = node.context!.findRenderObject()!;
    final Object? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is RenderBox) {
      return viewport.localToGlobal(Offset.zero) & viewport.size;
    }
    return Offset.zero & const Size(800, 632);
  }

  void expectFocusInView(WidgetTester tester, String step) {
    final node = FocusManager.instance.primaryFocus;
    expect(node, isNotNull, reason: step);
    final rect = node!.rect;
    final area = seenArea(tester, node);
    expect(
      rect.top >= area.top - 0.5 && rect.bottom <= area.bottom + 0.5,
      isTrue,
      reason:
          '$step: ${focusedHook()} at $rect is not fully inside $area '
          '(hidden focus, WCAG 2.4.11)',
    );
  }

  /// The snippet rows fully in view, top to bottom.
  List<int> snippetRowsFullyInView(WidgetTester tester) {
    final viewport = tester.getRect(
      find.descendant(
        of: find.byType(SnippetsScreen),
        matching: find.byType(Viewport),
      ),
    );
    final rows = <(double, int)>[];
    for (final e in find.byType(SnippetRow).evaluate()) {
      final row = e.widget as SnippetRow;
      final r = tester.getRect(find.byWidget(row));
      if (r.top >= viewport.top - 0.5 && r.bottom <= viewport.bottom + 0.5) {
        rows.add((r.top, row.item.id));
      }
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final r in rows) r.$2];
  }

  group('Snippets, list wheel-scrolled to the bottom (QA-M14-5)', () {
    testWidgets('Tab from the Snippets tab goes to New snippet', (
      tester,
    ) async {
      fillSnippets(30);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 20000);
      await tapTab(tester, 'main-tab-snippets');
      expect(focusedHook(), 'main-tab-snippets');

      await press(tester);

      expect(focusedHook(), 'snippet-new');
      expectFocusInView(tester, 'Tab from the Snippets tab');
    });

    testWidgets('the next Tab enters the list at the first row fully in view, '
        'and the list does not move; Enter copies that row', (tester) async {
      fillSnippets(30);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 20000);
      await tapTab(tester, 'main-tab-snippets');
      final firstInView = snippetRowsFullyInView(tester).first;
      final before = tester.getRect(hook('snippet-row-$firstInView'));

      await press(tester);
      await press(tester);

      expect(focusedHook(), 'snippet-row-$firstInView');
      expectFocusInView(tester, 'Tab from New snippet');
      expect(
        tester.getRect(hook('snippet-row-$firstInView')).top,
        before.top,
        reason: 'the list moved',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(source.ownWrites, [service.snippets.textOf(firstInView)]);
    });

    for (final (label, dy) in [
      ('the bottom', 20000.0),
      ('the middle', 700.0),
    ]) {
      testWidgets('scrolled to $label: every Tab and Shift+Tab from the '
          'Snippets tab keeps the focused control fully in view', (
        tester,
      ) async {
        fillSnippets(30);
        await show(tester);
        await tapTab(tester, 'main-tab-snippets');
        await wheel(tester, SnippetsScreen, dy);
        await tapTab(tester, 'main-tab-snippets');
        for (var i = 1; i <= 80; i++) {
          await press(tester);
          expectFocusInView(tester, 'Tab $i');
        }
        await wheel(tester, SnippetsScreen, -dy / 2);
        await tapTab(tester, 'main-tab-snippets');
        for (var i = 1; i <= 80; i++) {
          await press(tester, shift: true);
          expectFocusInView(tester, 'Shift+Tab $i');
        }
      });
    }

    testWidgets('Shift+Tab around from the History tab lands on the last row '
        'fully in view', (tester) async {
      fillSnippets(30);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      final lastInView = snippetRowsFullyInView(tester).last;
      await press(tester, shift: true);
      expect(focusedHook(), 'main-tab-history');

      await press(tester, shift: true);

      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<SnippetRow>()
            ?.item
            .id,
        lastInView,
        reason: 'focused: ${focusedHook()}',
      );
      expectFocusInView(tester, 'Shift+Tab around');
    });
  });

  group('History, list wheel-scrolled down (checked for QA-M14-5)', () {
    testWidgets('Tab from the History tab goes to the Snippets tab, then to '
        'the limit field, scrolled into view', (tester) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 20000);
      await tapTab(tester, 'main-tab-history');
      expect(focusedHook(), 'main-tab-history');

      await press(tester);
      expect(focusedHook(), 'main-tab-snippets');
      await press(tester);
      expect(focusedWidget<LimitField>(), isNotNull, reason: focusedHook());
      expectFocusInView(tester, 'Tab to the limit field');
    });

    for (final (label, dy) in [
      ('the bottom', 20000.0),
      ('the middle', 900.0),
    ]) {
      testWidgets('scrolled to $label: every Tab and Shift+Tab from the '
          'History tab keeps the focused control fully in view', (
        tester,
      ) async {
        fillHistory(60);
        await show(tester);
        await wheel(tester, HistoryScreen, dy);
        await tapTab(tester, 'main-tab-history');
        for (var i = 1; i <= 80; i++) {
          await press(tester);
          expectFocusInView(tester, 'Tab $i');
        }
        await wheel(tester, HistoryScreen, dy);
        await tapTab(tester, 'main-tab-history');
        for (var i = 1; i <= 80; i++) {
          await press(tester, shift: true);
          expectFocusInView(tester, 'Shift+Tab $i');
        }
      });
    }

    testWidgets('Enter after Tab never copies a history row out of view', (
      tester,
    ) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 20000);
      await tapTab(tester, 'main-tab-history');
      for (var i = 1; i <= 40; i++) {
        await press(tester);
        final row = focusedWidget<HistoryRow>();
        if (row != null) expectFocusInView(tester, 'Tab $i on a row');
      }
    });
  });

  group('a text-size change while a Snippets row has the focus (BUG-T2)', () {
    // Every row gets taller, so the focused row lands far below the view:
    // it was dropped and the focus jumped to another row's hidden control.
    for (final size in [const Size(520, 400), const Size(800, 632)]) {
      testWidgets('${size.width.toInt()} px: the same control keeps the '
          'focus, in view, and Shift+Tab and Tab go to its neighbours', (
        tester,
      ) async {
        fillSnippets(40);
        await show(tester, size: size);
        await tapTab(tester, 'main-tab-snippets');
        await wheel(tester, SnippetsScreen, 900);
        await tapTab(tester, 'main-tab-snippets');
        await press(tester); // New snippet
        await press(tester); // the first row fully in view
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final hookBefore = focusedHook();
        expect(hookBefore, startsWith('snippet-row-'));
        final id = int.parse(hookBefore!.substring('snippet-row-'.length));
        final items = service.snippets.items;
        final at = items.indexWhere((s) => s.id == id);
        final previousRow = items[at - 1].id;

        textScale.value = 2;
        await tester.pumpAndSettle();

        expect(focusedHook(), hookBefore, reason: 'the focus moved away');
        expectFocusInView(tester, 'after the text-size change');
        // At 200% text the row actions are in the "More" menu.
        await press(tester, shift: true);
        expect(focusedHook(), 'snippet-more-$previousRow');
        expectFocusInView(tester, 'Shift+Tab after the text-size change');
        await press(tester);
        expect(focusedHook(), hookBefore);
        expectFocusInView(tester, 'Tab back');
        await press(tester);
        expect(focusedHook(), 'snippet-more-$id');
        expectFocusInView(tester, 'Tab on');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
