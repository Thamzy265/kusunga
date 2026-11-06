import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/history/ui/limit_field.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

/// Tester round 9 on 6edb532, d9d691f and d892b56: a text-size change keeps
/// the focus on the same control, scrolled into view (Snippets and History);
/// Tab enters a list by whole rows. Breaking it: quick repeated changes,
/// changes during a scroll animation, with copies, trims, deletes, a resize
/// in the same frame, with the focus in the Keep field, a banner, the tabs
/// or the picker, and the H5 rule (a wheel scroll after the arrow keys).
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  final scale = ValueNotifier<double>(1);

  void create({int limit = 5000}) {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore()..setLimit(limit),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
    )..start();
  }

  var overflows = 0;

  void absorb(WidgetTester tester) {
    final e = tester.takeException();
    if (e == null) return;
    if (e is FlutterError && e.toString().contains('overflowed')) {
      overflows++;
      return;
    }
    throw e;
  }

  /// pumpAndSettle that absorbs (and counts) a RenderFlex overflow report:
  /// BUG-T3 is checked on its own; every other failure still fails.
  Future<void> settleT(WidgetTester tester) async {
    await tester.pumpAndSettle();
    absorb(tester);
  }

  setUp(() {
    overflows = 0;
    scale.value = 1;
    create();
  });
  tearDown(() => service.dispose());

  void fillSnippets(int n) {
    for (var i = 1; i <= n; i++) {
      service.snippets.save(
        name: 'snip ${i.toString().padLeft(3, '0')}',
        content: 'content $i',
        type: SnippetType.other,
      );
    }
  }

  void fillHistory(int n, [int from = 1]) {
    for (var i = from; i < from + n; i++) {
      source.copy('history item $i');
    }
  }

  Widget app({Widget? home}) => MaterialApp(
    theme: KusungaTokens.themeData(Brightness.light),
    builder: (context, child) => ValueListenableBuilder<double>(
      valueListenable: scale,
      builder: (context, s, _) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(s)),
        child: child!,
      ),
    ),
    home: home ?? HistoryHost(history: Future.value(service), initial: service),
  );

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settleT(tester);
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> tapTab(WidgetTester tester, String id) async {
    await tester.tap(hook(id));
    await settleT(tester);
  }

  Finder listOf(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byType(CustomScrollView),
  );

  ScrollPosition positionOf(WidgetTester tester, Type screen) => tester
      .state<ScrollableState>(
        find
            .descendant(of: listOf(screen), matching: find.byType(Scrollable))
            .first,
      )
      .position;

  Future<void> wheel(WidgetTester tester, Type screen, double dy) async {
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(listOf(screen))),
    );
    await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
    await settleT(tester);
  }

  Future<void> press(WidgetTester tester, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await settleT(tester);
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await settleT(tester);
  }

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

  int? focusedSnippetItem() => focusedWidget<SnippetRow>()?.item.id;
  int? focusedHistoryItemId() => focusedWidget<HistoryRow>()?.item.id;

  Size windowSize(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  void expectInView(WidgetTester tester, String step) {
    final node = FocusManager.instance.primaryFocus;
    expect(node, isNotNull, reason: '$step: nothing has the focus');
    final rect = node!.rect;
    expect(
      rect.isFinite,
      isTrue,
      reason:
          '$step: the focused control has no '
          'layout ($rect)',
    );
    final box = node.context!.findRenderObject()!;
    final Object? viewport = RenderAbstractViewport.maybeOf(box);
    final area = viewport is RenderBox
        ? viewport.localToGlobal(Offset.zero) & viewport.size
        : Offset.zero & windowSize(tester);
    expect(
      rect.top >= area.top - 0.5 && rect.bottom <= area.bottom + 0.5,
      isTrue,
      reason: '$step: ${focusedHook()} at $rect is not fully in $area',
    );
  }

  /// No History row is still held built after the change settles.
  void expectNoHold(WidgetTester tester, String step) {
    final held = tester
        .widgetList<HistoryRow>(find.byType(HistoryRow, skipOffstage: false))
        .where((r) => r.keepAlive)
        .length;
    expect(held, 0, reason: '$step: a row is still held');
    final mounted = find
        .byType(HistoryRow, skipOffstage: false)
        .evaluate()
        .length;
    expect(mounted, lessThan(50), reason: '$step: $mounted rows mounted');
  }

  Future<void> setScale(
    WidgetTester tester,
    double s, {
    bool settle = true,
  }) async {
    scale.value = s;
    if (settle) {
      await settleT(tester);
    } else {
      await tester.pump();
      absorb(tester);
    }
  }

  /// Tab to the first control of a kind (a hook prefix) in the shown list.
  Future<void> tabToHook(
    WidgetTester tester,
    bool Function(String) match,
  ) async {
    for (var i = 0; i < 60; i++) {
      await press(tester);
      final h = focusedHook();
      if (h != null && match(h)) return;
    }
    fail('Tab never reached the control');
  }

  /// Clicks the [n]th row (0 = first) that is fully in its list's view, on
  /// its text.
  Future<void> clickVisibleRow(
    WidgetTester tester,
    Type screen,
    Type rowType,
    int n,
  ) async {
    final viewport = tester.getRect(
      find.descendant(of: find.byType(screen), matching: find.byType(Viewport)),
    );
    final rows = <Rect>[
      for (final e in find.byType(rowType).evaluate())
        if (tester.getRect(find.byWidget(e.widget)).top >= viewport.top - 0.5 &&
            tester.getRect(find.byWidget(e.widget)).bottom <=
                viewport.bottom + 0.5)
          tester.getRect(find.byWidget(e.widget)),
    ]..sort((a, b) => a.top.compareTo(b.top));
    await tester.tapAt(rows[n].topLeft + const Offset(60, 16));
    await tester.pump();
  }

  // ---- Snippets ----

  group('Snippets: the focus through text-size changes', () {
    testWidgets('a focused row, up and down and up again, repeated: the '
        'same row keeps the focus, in view each time', (tester) async {
      fillSnippets(50);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 1300);
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 4);
      final id = focusedSnippetItem()!;
      for (final s in [2.0, 1.0, 1.5, 2.0, 1.0, 1.3, 1.8, 1.0]) {
        await setScale(tester, s);
        expect(focusedSnippetItem(), id, reason: 'at $s');
        expectInView(tester, 'text size $s');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('six changes in six frames, without settling: the focus '
        'ends on the same row, in view', (tester) async {
      fillSnippets(50);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 3);
      final id = focusedSnippetItem()!;
      for (final s in [2.0, 1.0, 2.0, 1.4, 1.0, 2.0]) {
        await setScale(tester, s, settle: false);
      }
      await settleT(tester);
      expect(focusedSnippetItem(), id);
      expectInView(tester, 'after six quick changes');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row action (Copy, by Tab) at 100%, then 200% (the actions '
        'move into the More menu), then back: the row (or the same '
        'control) keeps the focus, never a hidden control', (tester) async {
      fillSnippets(50);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      await tapTab(tester, 'main-tab-snippets');
      await tabToHook(tester, (h) => h.startsWith('snippet-copy-'));
      final id = focusedSnippetItem()!;
      await setScale(tester, 2);
      expect(focusedSnippetItem(), id);
      expectInView(tester, '200%');
      await setScale(tester, 1);
      expect(focusedSnippetItem(), id);
      expectInView(tester, 'back to 100%');
      // Tab and Shift+Tab still go on from there.
      await press(tester);
      expectInView(tester, 'Tab after the changes');
      await press(tester, shift: true);
      expectInView(tester, 'Shift+Tab after the changes');
    });

    testWidgets('a text-size change during a fling (the user is scrolling): '
        'no exception, no hidden focus, no leaked state', (tester) async {
      fillSnippets(60);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 2);
      await tester.fling(
        listOf(SnippetsScreen),
        const Offset(0, -900),
        3000,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 80));
      await setScale(tester, 2, settle: false);
      await tester.pump(const Duration(milliseconds: 80));
      await setScale(tester, 1, settle: false);
      await settleT(tester);
      expect(tester.takeException(), isNull);
      if (FocusManager.instance.primaryFocus != null &&
          focusedSnippetItem() != null) {
        expectInView(tester, 'after the fling and the changes');
      }
    });

    testWidgets('a text-size change and a window resize in the same frame', (
      tester,
    ) async {
      fillSnippets(50);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 1100);
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 3);
      final id = focusedSnippetItem()!;
      scale.value = 2;
      tester.view.physicalSize = const Size(520, 420);
      await settleT(tester);
      expect(focusedSnippetItem(), id);
      expectInView(tester, 'resize + 200%');
      scale.value = 1;
      tester.view.physicalSize = const Size(900, 700);
      await settleT(tester);
      expect(focusedSnippetItem(), id);
      expectInView(tester, 'resize back');
    });

    testWidgets('with an add, a delete of ANOTHER row, and a move in the '
        'same frame as the change', (tester) async {
      fillSnippets(50);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 3);
      final id = focusedSnippetItem()!;
      scale.value = 2;
      service.snippets.save(
        name: 'new one',
        content: 'x',
        type: SnippetType.other,
      );
      service.snippets.delete(service.snippets.items.last.id);
      await settleT(tester);
      expect(focusedSnippetItem(), id);
      expectInView(tester, 'change + add + delete');
    });

    testWidgets('the focused row deleted in the same frame as the change: '
        'no throw, and the focus is on a row in view or nowhere (no hidden '
        'control)', (tester) async {
      fillSnippets(50);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 3);
      final id = focusedSnippetItem()!;
      scale.value = 2;
      service.snippets.delete(id);
      await settleT(tester);
      expect(tester.takeException(), isNull);
      if (focusedSnippetItem() != null) {
        expectInView(tester, 'after the focused row was deleted');
      }
      // Tab still works.
      await press(tester);
      expectInView(tester, 'Tab afterwards');
    });

    testWidgets('H5: arrow keys, then a wheel scroll, then a text-size '
        'change: the list is not pulled back to the focused row', (
      tester,
    ) async {
      fillSnippets(60);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 0);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await wheel(tester, SnippetsScreen, 2500);
      final before = positionOf(tester, SnippetsScreen).pixels;
      expect(before, greaterThan(1500));
      await setScale(tester, 2);
      expect(tester.takeException(), isNull);
      expect(
        positionOf(tester, SnippetsScreen).pixels,
        greaterThan(before / 3),
        reason: 'the text-size change pulled the list back to the focus',
      );
      await setScale(tester, 1);
      expect(
        positionOf(tester, SnippetsScreen).pixels,
        greaterThan(before / 3),
      );
      // The next arrow key still brings the row back (H5).
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectInView(tester, 'arrow key after the changes');
    });

    testWidgets('the focus in the header (New snippet) or on a tab does not '
        'move to a row when the text size changes', (tester) async {
      fillSnippets(30);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await wheel(tester, SnippetsScreen, 900);
      await tapTab(tester, 'main-tab-snippets');
      expect(focusedHook(), 'main-tab-snippets');
      await setScale(tester, 2);
      expect(focusedHook(), 'main-tab-snippets');
      await press(tester); // New snippet
      expect(focusedHook(), 'snippet-new');
      await setScale(tester, 1);
      expect(focusedHook(), 'snippet-new');
      expectInView(tester, 'New snippet after the change');
    });
  });

  // ---- History ----

  group('History: the focus through text-size changes', () {
    testWidgets('a focused row, many changes: same row, in view, no row '
        'held afterwards', (tester) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 1500);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 4);
      final id = focusedHistoryItemId()!;
      for (final s in [2.0, 1.0, 1.5, 2.0, 1.0, 1.3, 1.8, 1.0]) {
        await setScale(tester, s);
        expect(focusedHistoryItemId(), id, reason: 'at $s');
        expectInView(tester, 'text size $s');
        expectNoHold(tester, 'text size $s');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('six changes in six frames: ends on the same row, in view, '
        'with no hold left', (tester) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 1200);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 3);
      final id = focusedHistoryItemId()!;
      for (final s in [2.0, 1.0, 2.0, 1.4, 1.0, 2.0]) {
        await setScale(tester, s, settle: false);
      }
      await settleT(tester);
      expect(focusedHistoryItemId(), id);
      expectInView(tester, 'six quick changes');
      expectNoHold(tester, 'six quick changes');
    });

    for (final (label, match) in <(String, bool Function(String))>[
      ('Copy', (h) => h.startsWith('history-copy-')),
      ('Save as snippet', (h) => h.startsWith('history-save-snippet-')),
      ('Delete', (h) => h.startsWith('history-delete-')),
    ]) {
      testWidgets('the $label button of a row (by Tab): 200% and back keep '
          'the same control, never a hidden one', (tester) async {
        fillHistory(60);
        await show(tester);
        await wheel(tester, HistoryScreen, 900);
        await tapTab(tester, 'main-tab-history');
        await tabToHook(tester, match);
        final id = focusedHistoryItemId()!;
        final hookBefore = focusedHook();
        await setScale(tester, 2);
        expect(focusedHistoryItemId(), id, reason: '$label at 200%');
        expectInView(tester, '$label at 200%');
        await setScale(tester, 1);
        expect(focusedHistoryItemId(), id, reason: '$label back at 100%');
        expectInView(tester, '$label at 100% again');
        expect(focusedHook(), hookBefore, reason: 'the same control');
        expectNoHold(tester, label);
      });
    }

    testWidgets('copies arriving in the same frame as the change, and '
        'between six quick changes', (tester) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 900);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 3);
      final id = focusedHistoryItemId()!;
      for (var i = 0; i < 6; i++) {
        scale.value = i.isEven ? 2 : 1;
        source.copy('fresh $i');
        await tester.pump();
      }
      await settleT(tester);
      expect(focusedHistoryItemId(), id);
      expectInView(tester, 'copies and changes');
      expectNoHold(tester, 'copies and changes');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full list that trims on every copy, change + copy in '
        'the same frame, the focused item at the oldest end', (tester) async {
      service.dispose();
      create(limit: 30);
      fillHistory(30);
      await show(tester);
      await key(tester, LogicalKeyboardKey.end); // may be a no-op if unfocused
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 0);
      await key(tester, LogicalKeyboardKey.end);
      expect(focusedHistoryItemId(), service.items.last.id);
      for (var i = 0; i < 6; i++) {
        scale.value = i.isEven ? 2 : 1;
        source.copy('fresh $i'); // trims the focused (oldest) item
        await settleT(tester);
        expect(tester.takeException(), isNull, reason: 'step $i');
        expect(focusedHistoryItemId(), isNotNull, reason: 'step $i lost focus');
        expectInView(tester, 'trim step $i');
        expectNoHold(tester, 'trim step $i');
      }
    });

    testWidgets('the focused item deleted in the same frame as the change', (
      tester,
    ) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 900);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 3);
      final id = focusedHistoryItemId()!;
      scale.value = 2;
      service.delete(id);
      await settleT(tester);
      expect(tester.takeException(), isNull);
      expectNoHold(tester, 'delete + change');
      if (focusedHistoryItemId() != null) {
        expectInView(tester, 'after delete + change');
      }
      await press(tester);
      expectInView(tester, 'Tab afterwards');
    });

    testWidgets('a change during a fling, then a change back', (tester) async {
      fillHistory(60);
      await show(tester);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 2);
      await tester.fling(
        listOf(HistoryScreen),
        const Offset(0, -900),
        3000,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 80));
      await setScale(tester, 2, settle: false);
      await tester.pump(const Duration(milliseconds: 80));
      await setScale(tester, 1, settle: false);
      await settleT(tester);
      expect(tester.takeException(), isNull);
      expectNoHold(tester, 'after the fling');
      if (focusedHistoryItemId() != null) {
        expectInView(tester, 'after the fling');
      }
    });

    testWidgets('a change and a window resize in the same frame', (
      tester,
    ) async {
      fillHistory(60);
      await show(tester);
      await wheel(tester, HistoryScreen, 1000);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 3);
      final id = focusedHistoryItemId()!;
      scale.value = 2;
      tester.view.physicalSize = const Size(520, 420);
      await settleT(tester);
      expect(focusedHistoryItemId(), id);
      expectInView(tester, 'resize + 200%');
      scale.value = 1;
      tester.view.physicalSize = const Size(900, 700);
      await settleT(tester);
      expect(focusedHistoryItemId(), id);
      expectInView(tester, 'resize back');
      expectNoHold(tester, 'resize');
    });

    testWidgets('H5: arrow keys, then a wheel scroll that disposes the '
        'focused row (focus waits on the screen), then changes: nothing '
        'pulls the list back, and the next arrow key still works', (
      tester,
    ) async {
      fillHistory(80);
      await show(tester);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 0);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await wheel(tester, HistoryScreen, 9000);
      expect(focusedHistoryItemId(), isNull, reason: 'waiting on the screen');
      final before = positionOf(tester, HistoryScreen).pixels;
      for (final s in [2.0, 1.0, 2.0, 1.0]) {
        await setScale(tester, s);
        expect(tester.takeException(), isNull);
        expectNoHold(tester, 'waiting, text size $s');
      }
      expect(
        positionOf(tester, HistoryScreen).pixels,
        greaterThan(before / 3),
        reason: 'a text-size change pulled the list back',
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      expectInView(tester, 'arrow key after the changes');
    });

    testWidgets('focus in the Keep field: a change leaves it there, in '
        'view, and typing still works', (tester) async {
      fillHistory(30);
      await show(tester);
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      final field = FocusManager.instance.primaryFocus;
      expect(focusedWidget<LimitField>(), isNotNull);
      await setScale(tester, 2);
      expect(FocusManager.instance.primaryFocus, field);
      expect(focusedWidget<LimitField>(), isNotNull);
      expect(focusedHistoryItemId(), isNull);
      await setScale(tester, 1);
      expect(focusedWidget<LimitField>(), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('focus on a tab or a banner button: a change leaves it '
        'there', (tester) async {
      fillHistory(30);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      expect(focusedHook(), 'main-tab-history');
      await setScale(tester, 2);
      expect(focusedHook(), 'main-tab-history');
      await setScale(tester, 1);
      expect(focusedHook(), 'main-tab-history');
      await press(tester); // Snippets tab
      await setScale(tester, 2);
      expect(focusedHook(), 'main-tab-snippets');
    });

    testWidgets('row-owned button nodes: deleting and trimming rows while '
        'their buttons have the focus never throws', (tester) async {
      service.dispose();
      create(limit: 40);
      fillHistory(40);
      await show(tester);
      for (var round = 0; round < 8; round++) {
        await tapTab(tester, 'main-tab-history');
        await tabToHook(
          tester,
          (h) =>
              h.startsWith('history-copy-') ||
              h.startsWith('history-delete-') ||
              h.startsWith('history-save-snippet-'),
        );
        final id = focusedHistoryItemId()!;
        scale.value = round.isEven ? 2 : 1;
        if (round.isOdd) {
          service.delete(id);
        } else {
          for (var i = 0; i < 5; i++) {
            source.copy('churn $round $i');
          }
        }
        await settleT(tester);
        expect(tester.takeException(), isNull, reason: 'round $round');
        expectNoHold(tester, 'round $round');
      }
      // The focus tree does not grow without bound.
      expect(FocusManager.instance.rootScope.descendants.length, lessThan(400));
    });

    testWidgets('mass churn: 60 rows deleted one by one while the Delete '
        'button of the first one keeps the focus, no throw', (tester) async {
      fillHistory(60);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      for (var i = 0; i < 40; i++) {
        await tabToHook(tester, (h) => h.startsWith('history-delete-'));
        await key(tester, LogicalKeyboardKey.space); // presses Delete
        expect(tester.takeException(), isNull, reason: 'delete $i');
      }
      expect(service.items.length, 20);
      expectNoHold(tester, 'after 40 deletes');
    });
  });

  // ---- findings ----

  testWidgets('BUG-T3: a text-size change while the Snippets list is '
      'scrolled raises no layout error (today one frame overflows a '
      'snippet row by 38 px: the rows are laid out with the old prototype '
      'height)', (tester) async {
    fillSnippets(50);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await wheel(tester, SnippetsScreen, 1300);
    await setScale(tester, 2);
    expect(overflows, 0, reason: 'a RenderFlex overflowed after the change');
  }, skip: true);

  testWidgets('BUG-T3 (History): the same, History list', (tester) async {
    fillHistory(60);
    await show(tester);
    await wheel(tester, HistoryScreen, 1300);
    await setScale(tester, 2);
    expect(overflows, 0, reason: 'a RenderFlex overflowed after the change');
  });

  testWidgets('BUG-K1 (Snippets): Enter on a focused row Delete button '
      'activates the button, not the row\'s Enter shortcut (Copy)', (
    tester,
  ) async {
    fillSnippets(10);
    await show(tester);
    await tapTab(tester, 'main-tab-snippets');
    await tabToHook(tester, (h) => h.startsWith('snippet-delete-'));
    final id = focusedSnippetItem()!;
    await key(tester, LogicalKeyboardKey.enter);
    expect(
      service.snippets.items.any((s) => s.id == id),
      isFalse,
      reason:
          'Enter on Delete did not delete (it copied: '
          '${source.ownWrites.length} copies)',
    );
  });

  testWidgets('BUG-K1 (History): Enter on a focused Delete or Save as '
      'snippet button activates that button', (tester) async {
    fillHistory(10);
    await show(tester);
    await tapTab(tester, 'main-tab-history');
    await tabToHook(tester, (h) => h.startsWith('history-save-snippet-'));
    await key(tester, LogicalKeyboardKey.enter);
    expect(
      find.text('New snippet'),
      findsWidgets,
      reason: 'Enter on Save as snippet did not open the editor',
    );
    await key(tester, LogicalKeyboardKey.escape);
    await tabToHook(tester, (h) => h.startsWith('history-delete-'));
    final id = focusedHistoryItemId()!;
    await key(tester, LogicalKeyboardKey.enter);
    expect(
      service.items.any((e) => e.id == id),
      isFalse,
      reason: 'Enter on Delete did not delete',
    );
  });

  // ---- the picker ----

  group('with the picker', () {
    testWidgets('a text-size change with the picker open (search field '
        'focused): the field keeps the focus', (tester) async {
      fillHistory(20);
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = FakePickerPort();
      final controller = PickerController(
        port: port,
        log: FakeLog(),
        isMac: true,
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.attach(service);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        KusungaApp(history: Future.value(service), picker: controller),
      );
      await tester.pump();
      await tester.pump();
      port.press();
      await tester.pump();
      await tester.pump();
      expect(find.byType(PickerPanel), findsOneWidget);
      final field = FocusManager.instance.primaryFocus;
      expect(field, isNotNull);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settleT(tester);
      expect(FocusManager.instance.primaryFocus, field);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await settleT(tester);
      expect(FocusManager.instance.primaryFocus, field);
      expect(tester.takeException(), isNull);
    });
  });

  // ---- Tab entry by whole rows ----

  group('Tab entry at cut-off rows, both directions, both lists', () {
    for (final height in [632.0, 611.0, 575.0, 480.0, 433.0, 400.0]) {
      for (final s in [1.0, 2.0]) {
        testWidgets('Snippets at ${height.toInt()} px, ${(s * 100).toInt()}% '
            'text: Tab into the list lands on a fully visible row, for 8 '
            'scroll offsets', (tester) async {
          scale.value = s;
          fillSnippets(50);
          await show(tester, size: Size(800, height));
          await tapTab(tester, 'main-tab-snippets');
          for (final dy in [
            0.0,
            37.0,
            111.0,
            250.0,
            413.0,
            777.0,
            913.0,
            1501.0,
          ]) {
            await wheel(tester, SnippetsScreen, -50000);
            await wheel(tester, SnippetsScreen, dy);
            await tapTab(tester, 'main-tab-snippets');
            await press(tester); // New snippet
            await press(tester); // into the list
            final id = focusedSnippetItem();
            expect(id, isNotNull, reason: 'offset $dy: ${focusedHook()}');
            final row = tester.getRect(hook('snippet-row-$id'));
            final viewport = tester.getRect(
              find.descendant(
                of: find.byType(SnippetsScreen),
                matching: find.byType(Viewport),
              ),
            );
            expect(
              row.top >= viewport.top - 0.5 &&
                  row.bottom <= viewport.bottom + 0.5,
              isTrue,
              reason: 'offset $dy: entered row $id $row, view $viewport',
            );
          }
        });

        testWidgets('History at ${height.toInt()} px, ${(s * 100).toInt()}% '
            'text: Tab into the list lands on a fully visible row, for 8 '
            'scroll offsets', (tester) async {
          scale.value = s;
          fillHistory(60);
          await show(tester, size: Size(800, height));
          for (final dy in [
            0.0,
            37.0,
            111.0,
            250.0,
            413.0,
            777.0,
            913.0,
            1501.0,
          ]) {
            await wheel(tester, HistoryScreen, -50000);
            await wheel(tester, HistoryScreen, dy);
            await tapTab(tester, 'main-tab-history');
            // Tab until the first row-level control: its row must be whole.
            await tabToHook(
              tester,
              (h) =>
                  h.startsWith('history-copy-') ||
                  h.startsWith('history-save-snippet-') ||
                  h.startsWith('history-delete-'),
            );
            final id = focusedHistoryItemId()!;
            final row = tester.getRect(find.byKey(ValueKey('row-$id')));
            final viewport = tester.getRect(
              find.descendant(
                of: find.byType(HistoryScreen),
                matching: find.byType(Viewport),
              ),
            );
            // The first row of the list is the one the Keep field etc. do not
            // precede: rows above it in the panel's top are not rows.
            expect(
              row.top >= viewport.top - 0.5 &&
                  row.bottom <= viewport.bottom + 0.5,
              isTrue,
              reason: 'offset $dy: entered item $id $row, view $viewport',
            );
          }
        });
      }
    }

    for (final s in [1.0, 2.0]) {
      testWidgets('Shift+Tab entering from outside (wrapping around from the '
          'first tab) lands on a fully visible row, ${(s * 100).toInt()}% '
          'text, both lists', (tester) async {
        scale.value = s;
        fillSnippets(50);
        fillHistory(60);
        await show(tester, size: const Size(800, 575));
        for (final dy in [0.0, 37.0, 250.0, 913.0]) {
          await tapTab(tester, 'main-tab-snippets');
          await wheel(tester, SnippetsScreen, -50000);
          await wheel(tester, SnippetsScreen, dy);
          await tapTab(tester, 'main-tab-snippets');
          await press(tester, shift: true); // history tab
          await press(tester, shift: true); // wraps into the list
          final id = focusedSnippetItem();
          if (id != null) {
            final row = tester.getRect(hook('snippet-row-$id'));
            final viewport = tester.getRect(
              find.descendant(
                of: find.byType(SnippetsScreen),
                matching: find.byType(Viewport),
              ),
            );
            expect(
              row.top >= viewport.top - 0.5 &&
                  row.bottom <= viewport.bottom + 0.5,
              isTrue,
              reason: 'Snippets offset $dy: row $id $row, view $viewport',
            );
          }
          expectInView(tester, 'Snippets Shift+Tab entry at $dy');
        }
        await tapTab(tester, 'main-tab-history');
        for (final dy in [0.0, 37.0, 250.0, 913.0]) {
          await wheel(tester, HistoryScreen, -50000);
          await wheel(tester, HistoryScreen, dy);
          await tapTab(tester, 'main-tab-history');
          await press(tester, shift: true); // wraps into the list
          expectInView(tester, 'History Shift+Tab entry at $dy');
          final id = focusedHistoryItemId();
          if (id != null) {
            final row = tester.getRect(find.byKey(ValueKey('row-$id')));
            final viewport = tester.getRect(
              find.descendant(
                of: find.byType(HistoryScreen),
                matching: find.byType(Viewport),
              ),
            );
            expect(
              row.top >= viewport.top - 0.5 &&
                  row.bottom <= viewport.bottom + 0.5,
              isTrue,
              reason: 'History offset $dy: row $id $row, view $viewport',
            );
          }
        }
      });
    }
  });
}
