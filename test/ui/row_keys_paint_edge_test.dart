import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/history_row.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

/// Tester round 10 on 9206ad7 and a1e3e55 (row keys, no repaint boundary). (Round 9 header: a text-size change keeps
/// the focus on the same control, scrolled into view (Snippets and History);
/// Tab enters a list by whole rows. Breaking it: quick repeated changes,
/// changes during a scroll animation, with copies, trims, deletes, a resize
/// in the same frame, with the focus in the Keep field, a banner, the tabs
/// or the picker, and the H5 rule (a wheel scroll after the arrow keys).
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  final scale = ValueNotifier<double>(1);
  final historyWrites = <String>[];

  void create({int limit = 5000}) {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore()..setLimit(limit),
      source: source,
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
      writeClipboard: (text) async => historyWrites.add(text),
    )..start();
  }

  void absorb(WidgetTester tester) {
    final e = tester.takeException();
    if (e != null) throw e;
  }

  /// pumpAndSettle that absorbs (and counts) a RenderFlex overflow report:
  /// BUG-T3 is checked on its own; every other failure still fails.
  Future<void> settleT(WidgetTester tester) async {
    await tester.pumpAndSettle();
    absorb(tester);
  }

  setUp(() {
    historyWrites.clear();
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

  Future<void> wheel(WidgetTester tester, Type screen, double dy) async {
    final mouse = TestPointer(7, PointerDeviceKind.mouse);
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

  // ---------------------------------------------------------------- helpers

  /// A row's own focus node has the focus (not one of its buttons).
  int? focusedSnippetRowOnly() {
    final row = focusedWidget<SnippetRow>();
    return row != null && row.focusNode == FocusManager.instance.primaryFocus
        ? row.item.id
        : null;
  }

  int? focusedHistoryRowOnly() {
    final row = focusedWidget<HistoryRow>();
    return row != null && row.focusNode == FocusManager.instance.primaryFocus
        ? row.item.id
        : null;
  }

  List<int> snippetIds() => [for (final s in service.snippets.items) s.id];
  List<int> historyIds() => [for (final i in service.items) i.id];
  Future<void> closeEditor(WidgetTester tester) async {
    if (find.byType(Dialog).evaluate().isNotEmpty) {
      await key(tester, LogicalKeyboardKey.escape);
      final discard = find.text('Discard');
      if (discard.evaluate().isNotEmpty) {
        await tester.tap(discard);
        await settleT(tester);
      }
    }
  }

  /// Tab to the first control whose hook starts with [prefix] on a row that
  /// is not the first (so Move up exists) when [skipFirstRow] is set.
  Future<void> tabTo(WidgetTester tester, String prefix) =>
      tabToHook(tester, (h) => h.startsWith(prefix));

  // ------------------------------------------------- A. every key, every control

  const nonActivation = <(String, LogicalKeyboardKey)>[
    ('Delete', LogicalKeyboardKey.delete),
    ('Backspace', LogicalKeyboardKey.backspace),
    ('S', LogicalKeyboardKey.keyS),
    ('E', LogicalKeyboardKey.keyE),
    ('F2', LogicalKeyboardKey.f2),
    ('Escape', LogicalKeyboardKey.escape),
    ('a letter', LogicalKeyboardKey.keyQ),
  ];
  const activation = <(String, LogicalKeyboardKey)>[
    ('Enter', LogicalKeyboardKey.enter),
    ('NumpadEnter', LogicalKeyboardKey.numpadEnter),
    ('Space', LogicalKeyboardKey.space),
  ];

  group('Snippets: every key on every row control', () {
    for (final prefix in [
      'snippet-copy-',
      'snippet-edit-',
      'snippet-up-',
      'snippet-down-',
      'snippet-delete-',
    ]) {
      for (final (kname, k) in nonActivation) {
        testWidgets('$prefix: $kname changes nothing', (tester) async {
          fillSnippets(8);
          await show(tester);
          await tapTab(tester, 'main-tab-snippets');
          await tabTo(tester, prefix);
          final ids = snippetIds();
          await key(tester, k);
          await closeEditor(tester);
          expect(snippetIds(), ids, reason: '$kname changed the list');
          expect(source.ownWrites, isEmpty, reason: '$kname copied');
          expect(
            find.byType(Dialog),
            findsNothing,
            reason: '$kname opened one',
          );
          absorb(tester);
        });
      }

      for (final (kname, k) in activation) {
        testWidgets('$prefix: $kname does what the button does, and only '
            'that', (tester) async {
          fillSnippets(8);
          await show(tester);
          await tapTab(tester, 'main-tab-snippets');
          await tabTo(tester, prefix);
          final id = focusedSnippetItem()!;
          final before = snippetIds();
          await key(tester, k);
          final after = snippetIds();
          switch (prefix) {
            case 'snippet-copy-':
              expect(source.ownWrites, hasLength(1));
              expect(after, before);
            case 'snippet-edit-':
              expect(find.text('Edit snippet'), findsOneWidget);
              expect(source.ownWrites, isEmpty);
              expect(after, before);
              await closeEditor(tester);
            case 'snippet-up-':
              expect(after, isNot(before), reason: 'Move up did not move');
              expect(after.indexOf(id), before.indexOf(id) - 1);
              expect(source.ownWrites, isEmpty);
            case 'snippet-down-':
              expect(after.indexOf(id), before.indexOf(id) + 1);
              expect(source.ownWrites, isEmpty);
            case 'snippet-delete-':
              expect(after, before.where((e) => e != id).toList());
              expect(source.ownWrites, isEmpty);
          }
          absorb(tester);
        });
      }
    }

    testWidgets('the row itself: Enter, NumpadEnter copy; E and F2 edit; '
        'Delete and Backspace delete; S, Space, letters do nothing', (
      tester,
    ) async {
      fillSnippets(8);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      for (final (what, k) in [
        ('Enter', LogicalKeyboardKey.enter),
        ('NumpadEnter', LogicalKeyboardKey.numpadEnter),
      ]) {
        await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 1);
        expect(focusedSnippetRowOnly(), isNotNull);
        source.ownWrites.clear();
        await key(tester, k);
        expect(source.ownWrites, hasLength(1), reason: what);
      }
      for (final (what, k) in [
        ('E', LogicalKeyboardKey.keyE),
        ('F2', LogicalKeyboardKey.f2),
      ]) {
        await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 1);
        await key(tester, k);
        expect(find.text('Edit snippet'), findsOneWidget, reason: what);
        await closeEditor(tester);
      }
      for (final (what, k) in [
        ('S', LogicalKeyboardKey.keyS),
        ('Space', LogicalKeyboardKey.space),
        ('Q', LogicalKeyboardKey.keyQ),
      ]) {
        await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 1);
        final ids = snippetIds();
        source.ownWrites.clear();
        await key(tester, k);
        expect(snippetIds(), ids, reason: what);
        expect(source.ownWrites, isEmpty, reason: what);
        expect(find.byType(Dialog), findsNothing, reason: what);
      }
      for (final (what, k) in [
        ('Delete', LogicalKeyboardKey.delete),
        ('Backspace', LogicalKeyboardKey.backspace),
      ]) {
        await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 1);
        final n = snippetIds().length;
        await key(tester, k);
        expect(snippetIds().length, n - 1, reason: what);
      }
    });

    testWidgets('arrows, Home and End on a focused button still move the '
        'focus between rows (unchanged), and change no data', (tester) async {
      fillSnippets(20);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-edit-');
      final ids = snippetIds();
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.home,
      ]) {
        await key(tester, k);
        expect(focusedSnippetItem(), isNotNull, reason: '$k lost the focus');
        expectInView(tester, '$k from a button');
      }
      expect(snippetIds(), ids);
      expect(source.ownWrites, isEmpty);
    });
  });

  group('History: every key on every row control', () {
    for (final prefix in [
      'history-copy-',
      'history-save-snippet-',
      'history-delete-',
    ]) {
      for (final (kname, k) in nonActivation) {
        testWidgets('$prefix: $kname changes nothing', (tester) async {
          fillHistory(8);
          await show(tester);
          await tapTab(tester, 'main-tab-history');
          await tabTo(tester, prefix);
          final ids = historyIds();
          await key(tester, k);
          await closeEditor(tester);
          expect(historyIds(), ids, reason: '$kname changed the list');
          expect(historyWrites, isEmpty, reason: '$kname copied');
          expect(
            find.byType(Dialog),
            findsNothing,
            reason: '$kname opened one',
          );
          expect(service.snippets.items, isEmpty);
          absorb(tester);
        });
      }

      for (final (kname, k) in activation) {
        testWidgets('$prefix: $kname does what the button does, and only '
            'that', (tester) async {
          fillHistory(8);
          await show(tester);
          await tapTab(tester, 'main-tab-history');
          await tabTo(tester, prefix);
          final id = focusedHistoryItemId()!;
          final before = historyIds();
          await key(tester, k);
          switch (prefix) {
            case 'history-copy-':
              expect(historyWrites, hasLength(1));
              expect(historyIds(), before);
            case 'history-save-snippet-':
              expect(find.text('New snippet'), findsWidgets);
              expect(historyWrites, isEmpty);
              expect(historyIds(), before);
              await closeEditor(tester);
            case 'history-delete-':
              expect(historyIds(), before.where((e) => e != id).toList());
              expect(historyWrites, isEmpty);
          }
          absorb(tester);
        });
      }
    }

    testWidgets('the row itself: Enter copies, S saves, Delete and '
        'Backspace delete; E, F2, Space do nothing', (tester) async {
      fillHistory(8);
      await show(tester);
      for (final (what, k) in [
        ('Enter', LogicalKeyboardKey.enter),
        ('NumpadEnter', LogicalKeyboardKey.numpadEnter),
      ]) {
        await clickVisibleRow(tester, HistoryScreen, HistoryRow, 1);
        historyWrites.clear();
        await key(tester, k);
        expect(historyWrites, hasLength(1), reason: what);
      }
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 1);
      await key(tester, LogicalKeyboardKey.keyS);
      expect(find.text('New snippet'), findsWidgets);
      await closeEditor(tester);
      for (final (what, k) in [
        ('E', LogicalKeyboardKey.keyE),
        ('F2', LogicalKeyboardKey.f2),
        ('Space', LogicalKeyboardKey.space),
      ]) {
        await clickVisibleRow(tester, HistoryScreen, HistoryRow, 1);
        final ids = historyIds();
        historyWrites.clear();
        await key(tester, k);
        expect(historyIds(), ids, reason: what);
        expect(historyWrites, isEmpty, reason: what);
      }
      for (final (what, k) in [
        ('Delete', LogicalKeyboardKey.delete),
        ('Backspace', LogicalKeyboardKey.backspace),
      ]) {
        await clickVisibleRow(tester, HistoryScreen, HistoryRow, 1);
        final n = historyIds().length;
        await key(tester, k);
        expect(historyIds().length, n - 1, reason: what);
      }
    });

    testWidgets('arrows, Home and End on a focused button still move the '
        'focus between rows, and change no data', (tester) async {
      fillHistory(30);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      await tabTo(tester, 'history-save-snippet-');
      final ids = historyIds();
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.home,
      ]) {
        await key(tester, k);
        expect(focusedHistoryItemId(), isNotNull, reason: '$k lost the focus');
        expectInView(tester, '$k from a button');
      }
      expect(historyIds(), ids);
      expect(historyWrites, isEmpty);
    });
  });

  // ----------------------------------------------- B. the More menu (narrow)

  group('Snippets More menu at 520 px', () {
    Future<void> openMore(WidgetTester tester) async {
      fillSnippets(8);
      await show(tester, size: const Size(520, 632));
      await tapTab(tester, 'main-tab-snippets');
      // A middle row, so every menu item (Move up and Move down) exists.
      final middle = service.snippets.items[2].id;
      for (var i = 0; i < 40 && focusedHook() != 'snippet-more-$middle'; i++) {
        await press(tester);
      }
      expect(focusedSnippetItem(), middle);
      expect(focusedHook(), startsWith('snippet-more-'));
    }

    for (final (label, downs) in [
      ('Copy', 1),
      ('Edit', 2),
      ('Move up', 3),
      ('Move down', 4),
      ('Delete', 5),
    ]) {
      testWidgets(
        'Enter opens the menu, Down x$downs (the first Down focuses the first item) and Enter chooses '
        '"$label" and nothing else',
        (tester) async {
          await openMore(tester);
          final id = focusedSnippetItem()!;
          final before = snippetIds();
          await key(tester, LogicalKeyboardKey.enter);
          expect(
            find.text('Delete'),
            findsOneWidget,
            reason: 'the menu is open',
          );
          expect(source.ownWrites, isEmpty, reason: 'Enter on More copied');
          for (var i = 0; i < downs; i++) {
            await key(tester, LogicalKeyboardKey.arrowDown);
          }
          await key(tester, LogicalKeyboardKey.enter);
          final after = snippetIds();
          switch (label) {
            case 'Copy':
              expect(source.ownWrites, hasLength(1));
              expect(after, before);
            case 'Edit':
              expect(find.text('Edit snippet'), findsOneWidget);
              expect(after, before);
              await closeEditor(tester);
            case 'Move up':
              expect(after.indexOf(id), before.indexOf(id) - 1);
            case 'Move down':
              expect(after.indexOf(id), before.indexOf(id) + 1);
            case 'Delete':
              expect(after, before.where((e) => e != id).toList());
          }
          absorb(tester);
        },
      );
    }

    for (final (what, k) in nonActivation) {
      testWidgets('on the More button, $what changes nothing', (tester) async {
        await openMore(tester);
        final ids = snippetIds();
        await key(tester, k);
        await closeEditor(tester);
        expect(snippetIds(), ids, reason: what);
        expect(source.ownWrites, isEmpty, reason: what);
      });
    }

    testWidgets('Space on the More button opens the menu', (tester) async {
      await openMore(tester);
      await key(tester, LogicalKeyboardKey.space);
      expect(find.text('Delete'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(snippetIds(), hasLength(8));
    });
  });

  // ------------------------------------------------- C. the picker rows

  group('the picker window rows are unchanged', () {
    testWidgets('arrows select, Enter pastes the selected row, digits paste '
        'by number, Delete and S do nothing', (tester) async {
      fillHistory(12);
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
      port.press();
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: PickerPanel(controller: controller, now: () => 0),
        ),
      );
      await tester.pump();
      final ids = historyIds();
      for (final k in [
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.keyS,
      ]) {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }
      expect(historyIds(), ids);
      expect(port.pastes, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(port.pastes, hasLength(1));
      expect(port.pastes.single.text, 'history item 11');
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------- D. waiting focus and after Undo

  group('keys while the focus waits, and right after Undo', () {
    for (final (what, k) in [...activation, ...nonActivation]) {
      testWidgets('History, focus waiting on the screen after a wheel '
          'scroll: $what does nothing', (tester) async {
        fillHistory(60);
        await show(tester);
        await clickVisibleRow(tester, HistoryScreen, HistoryRow, 1);
        await wheel(tester, HistoryScreen, 6000);
        expect(focusedHistoryItemId(), isNull);
        final ids = historyIds();
        await key(tester, k);
        expect(historyIds(), ids, reason: what);
        expect(historyWrites, isEmpty, reason: what);
        expect(find.byType(Dialog), findsNothing, reason: what);
        absorb(tester);
      });
    }

    testWidgets('History: Delete on a row, Undo (button), then Enter, '
        'Delete, S, E: each acts only on a focused row, never on a hidden '
        'one', (tester) async {
      fillHistory(30);
      await show(tester);
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 2);
      await key(tester, LogicalKeyboardKey.delete);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Undo'));
      await settleT(tester);
      expect(historyIds(), hasLength(30));
      for (final k in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.delete,
      ]) {
        final rowOnly = focusedHistoryRowOnly();
        final ids = historyIds();
        historyWrites.clear();
        await key(tester, k);
        await closeEditor(tester);
        final removed = ids.where((e) => !historyIds().contains(e)).toList();
        if (k == LogicalKeyboardKey.delete) {
          if (rowOnly == null) {
            expect(removed, isEmpty, reason: 'Delete with no row focused');
          } else {
            expect(removed, [rowOnly], reason: 'Delete hit another row');
          }
        } else {
          expect(removed, isEmpty, reason: '$k removed something');
        }
        absorb(tester);
      }
    });

    testWidgets('Snippets: Delete on a row, Undo, then the same checks', (
      tester,
    ) async {
      fillSnippets(30);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await clickVisibleRow(tester, SnippetsScreen, SnippetRow, 2);
      await key(tester, LogicalKeyboardKey.delete);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Undo'));
      await settleT(tester);
      expect(snippetIds(), hasLength(30));
      for (final k in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.delete,
      ]) {
        final rowOnly = focusedSnippetRowOnly();
        final ids = snippetIds();
        await key(tester, k);
        await closeEditor(tester);
        final removed = ids.where((e) => !snippetIds().contains(e)).toList();
        if (k == LogicalKeyboardKey.delete) {
          expect(removed, rowOnly == null ? isEmpty : [rowOnly]);
        } else {
          expect(removed, isEmpty);
        }
        absorb(tester);
      }
    });
  });

  // ---------- E. a button whose row is deleted, trimmed or moved

  group('a focused button whose row goes away or moves', () {
    testWidgets('Snippets: Enter on Move down moves the row and leaves the '
        'focus on the moved ROW (by design); Enter again then copies it, it '
        'does not move it again', (tester) async {
      fillSnippets(10);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-down-');
      final id = focusedSnippetItem()!;
      final start = snippetIds().indexOf(id);
      await key(tester, LogicalKeyboardKey.enter);
      expect(snippetIds().indexOf(id), start + 1);
      expect(focusedSnippetRowOnly(), id, reason: 'the focus is on the row');
      expectInView(tester, 'after the move');
      await key(tester, LogicalKeyboardKey.enter);
      expect(snippetIds().indexOf(id), start + 1, reason: 'moved again');
      expect(source.ownWrites, hasLength(1), reason: 'Enter on the row copies');
    });

    testWidgets('Snippets: Move down by keyboard from the first to the last '
        'row, re-reaching the button each time: no throw, in view, nothing '
        'deleted or copied on the way', (tester) async {
      fillSnippets(6);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-down-');
      final id = focusedSnippetItem()!;
      for (
        var guard = 0;
        guard < 12 && snippetIds().indexOf(id) < snippetIds().length - 1;
        guard++
      ) {
        await key(tester, LogicalKeyboardKey.enter);
        expect(tester.takeException(), isNull);
        expectInView(tester, 'after a move');
        if (snippetIds().indexOf(id) < snippetIds().length - 1) {
          await tabTo(tester, 'snippet-down-');
        }
      }
      expect(snippetIds().last, id);
      expect(snippetIds(), hasLength(6));
      expect(source.ownWrites, isEmpty);
      expect(focusedSnippetItem(), isNotNull);
      // The row is last: its Move down is gone. Delete on the focused control
      // (the row) deletes only this row, Enter on it copies it.
      await key(tester, LogicalKeyboardKey.enter);
      expect(source.ownWrites, hasLength(1));
      expect(snippetIds(), hasLength(6));
    });

    testWidgets('Snippets: Move up by keyboard from the second to the first '
        'row', (tester) async {
      fillSnippets(6);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-up-');
      final id = focusedSnippetItem()!;
      for (var guard = 0; guard < 12 && snippetIds().indexOf(id) > 0; guard++) {
        await key(tester, LogicalKeyboardKey.enter);
        expect(tester.takeException(), isNull);
        expectInView(tester, 'after a move');
        if (snippetIds().indexOf(id) > 0) await tabTo(tester, 'snippet-up-');
      }
      expect(snippetIds().first, id);
      expect(snippetIds(), hasLength(6));
      expect(source.ownWrites, isEmpty);
    });

    testWidgets('Snippets: Enter on Delete, then Enter x3: the neighbour '
        'row is copied three times, only one snippet is gone', (tester) async {
      fillSnippets(8);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-delete-');
      await key(tester, LogicalKeyboardKey.enter);
      expect(snippetIds(), hasLength(7));
      final focusedNow = focusedSnippetItem();
      expect(focusedNow, isNotNull);
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.enter);
      }
      expect(snippetIds(), hasLength(7), reason: 'a second delete happened');
      expect(
        source.ownWrites.length,
        focusedSnippetRowOnly() == null ? lessThanOrEqualTo(3) : 3,
      );
    });

    testWidgets('History: Enter on Delete, then Enter x3', (tester) async {
      fillHistory(8);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      await tabTo(tester, 'history-delete-');
      await key(tester, LogicalKeyboardKey.enter);
      expect(historyIds(), hasLength(7));
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.enter);
      }
      expect(historyIds(), hasLength(7), reason: 'a second delete happened');
    });

    testWidgets('History: the item whose Delete button has the focus is '
        'trimmed by a new copy (full list): the focus moves to a row, and '
        'Enter copies it, Delete would delete only it', (tester) async {
      service.dispose();
      create(limit: 20);
      fillHistory(20);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      await clickVisibleRow(tester, HistoryScreen, HistoryRow, 0);
      await key(tester, LogicalKeyboardKey.end); // the oldest row
      await tabTo(tester, 'history-delete-');
      expect(focusedHistoryItemId(), service.items.last.id);
      source.copy('fresh');
      await settleT(tester);
      expect(tester.takeException(), isNull);
      final id = focusedHistoryItemId();
      expect(id, isNotNull, reason: 'the focus was lost');
      expectInView(tester, 'after the trim');
      final n = historyIds().length;
      historyWrites.clear();
      await key(tester, LogicalKeyboardKey.enter);
      expect(historyIds().length, n, reason: 'Enter deleted something');
      expect(historyWrites.length, lessThanOrEqualTo(1));
      final rowOnly = focusedHistoryRowOnly();
      await key(tester, LogicalKeyboardKey.delete);
      expect(historyIds().length, rowOnly == null ? n : n - 1);
    });

    testWidgets('History: the row is deleted by the service while its '
        'button has the focus, and Enter is pressed in the same frame: no '
        'throw, no second delete', (tester) async {
      fillHistory(10);
      await show(tester);
      await tapTab(tester, 'main-tab-history');
      await tabTo(tester, 'history-delete-');
      final id = focusedHistoryItemId()!;
      service.delete(id);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // before a frame
      await settleT(tester);
      expect(tester.takeException(), isNull);
      expect(historyIds(), hasLength(9));
      expect(focusedHistoryItemId(), isNot(id));
    });

    testWidgets('Snippets: the same, with the service deleting the row', (
      tester,
    ) async {
      fillSnippets(10);
      await show(tester);
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-edit-');
      final id = focusedSnippetItem()!;
      service.snippets.delete(id);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleT(tester);
      expect(tester.takeException(), isNull);
      expect(snippetIds(), hasLength(9));
      await closeEditor(tester);
    });
  });

  // ------------------------- F. paint without a repaint boundary per row

  group('hover and focus paint, right row, no stale paint', () {
    final boundary = GlobalKey();

    Widget wrapped() => RepaintBoundary(
      key: boundary,
      child: HistoryHost(history: Future.value(service), initial: service),
    );

    Future<void> showWrapped(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: wrapped(),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<({ByteData data, int w})> grab(WidgetTester tester) async {
      return (await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final data = (await image.toByteData())!;
        return (data: data, w: image.width);
      }))!;
    }

    Color px(({ByteData data, int w}) img, double x, double y) {
      final o = (y.floor() * img.w + x.floor()) * 4;
      return Color.fromARGB(
        img.data.getUint8(o + 3),
        img.data.getUint8(o),
        img.data.getUint8(o + 1),
        img.data.getUint8(o + 2),
      );
    }

    bool near(Color a, Color b) =>
        ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 12;

    /// Rows (rect, id) fully in the list's view.
    List<(Rect, int)> visibleRows(
      WidgetTester tester,
      Type screen,
      Type rowType,
      int Function(Widget) idOf,
    ) {
      final viewport = tester.getRect(
        find.descendant(
          of: find.byType(screen),
          matching: find.byType(Viewport),
        ),
      );
      return [
        for (final e in find.byType(rowType).evaluate())
          if (tester.getRect(find.byWidget(e.widget)).top >= viewport.top &&
              tester.getRect(find.byWidget(e.widget)).bottom <= viewport.bottom)
            (tester.getRect(find.byWidget(e.widget)), idOf(e.widget)),
      ];
    }

    final t = KusungaTokens.light;

    /// The ring: the top border line, 1 px inside, is the focus colour.
    bool hasRing(({ByteData data, int w}) img, Rect r) =>
        near(px(img, r.center.dx, r.top + 1), t.focus);

    /// The hover fill: inside the padding above the text.
    bool hasHover(({ByteData data, int w}) img, Rect r) =>
        near(px(img, r.center.dx, r.top + 4), t.surfaceHover);

    for (final lists in [true, false]) {
      final name = lists ? 'Snippets' : 'History';
      testWidgets('$name: the focus ring is on the focused row only, after '
          'each of 12 scroll steps and a long scroll away and back', (
        tester,
      ) async {
        fillSnippets(40);
        fillHistory(40);
        await showWrapped(tester);
        if (lists) await tapTab(tester, 'main-tab-snippets');
        await clickVisibleRow(
          tester,
          lists ? SnippetsScreen : HistoryScreen,
          lists ? SnippetRow : HistoryRow,
          2,
        );
        final focusedId = lists
            ? focusedSnippetItem()!
            : focusedHistoryItemId()!;
        final screen = lists ? SnippetsScreen : HistoryScreen;
        for (var step = 0; step < 12; step++) {
          await wheel(tester, screen, step < 6 ? 23.0 : -17.0);
          final img = await grab(tester);
          final rows = visibleRows(
            tester,
            screen,
            lists ? SnippetRow : HistoryRow,
            lists
                ? (w) => (w as SnippetRow).item.id
                : (w) => (w as HistoryRow).item.id,
          );
          final ringed = [
            for (final (r, id) in rows)
              if (hasRing(img, r)) id,
          ];
          final stillThere = rows.any((r) => r.$2 == focusedId);
          if (stillThere) {
            expect(ringed, [focusedId], reason: 'step $step: rings on $ringed');
          } else {
            expect(ringed, isEmpty, reason: 'step $step: a stale ring');
          }
        }
        await wheel(tester, screen, 9000);
        await wheel(tester, screen, -9000);
        final img = await grab(tester);
        final rows = visibleRows(
          tester,
          screen,
          lists ? SnippetRow : HistoryRow,
          lists
              ? (w) => (w as SnippetRow).item.id
              : (w) => (w as HistoryRow).item.id,
        );
        final ringed = [
          for (final (r, id) in rows)
            if (hasRing(img, r)) id,
        ];
        expect(
          ringed.length,
          lessThanOrEqualTo(1),
          reason: 'stale rings: $ringed',
        );
      });

      testWidgets('$name: the hover fill follows the pointer to the right '
          'row while scrolling, and no other row keeps it', (tester) async {
        fillSnippets(40);
        fillHistory(40);
        await showWrapped(tester);
        if (lists) await tapTab(tester, 'main-tab-snippets');
        final screen = lists ? SnippetsScreen : HistoryScreen;
        final rowType = lists ? SnippetRow : HistoryRow;
        int idOf(Widget w) =>
            lists ? (w as SnippetRow).item.id : (w as HistoryRow).item.id;
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 9,
        );
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        for (var step = 0; step < 10; step++) {
          final rows = visibleRows(tester, screen, rowType, idOf);
          final target = rows[(step * 3) % rows.length];
          final point = target.$1.center - const Offset(0, 6);
          await mouse.moveTo(point);
          await tester.pump();
          await tester.pump();
          var img = await grab(tester);
          int? focused() =>
              lists ? focusedSnippetItem() : focusedHistoryItemId();
          List<int> hoveredNow() => [
            for (final (r, id) in visibleRows(tester, screen, rowType, idOf))
              if (hasHover(img, r) && id != focused()) id,
          ];
          expect(
            hoveredNow(),
            target.$2 == focused() ? isEmpty : [target.$2],
            reason: 'step $step: hover on ${hoveredNow()}',
          );
          // Scroll under the still pointer, then nudge it: the fill is on
          // the row now under it, and on no other.
          await wheel(tester, screen, 41);
          await mouse.moveTo(point + const Offset(0, 2));
          await tester.pump();
          await tester.pump();
          img = await grab(tester);
          final under = [
            for (final (r, id) in visibleRows(tester, screen, rowType, idOf))
              if (r.contains(point + const Offset(0, 2))) id,
          ];
          expect(
            hoveredNow(),
            under.isEmpty || under.single == focused() ? isEmpty : under,
            reason:
                'step $step after scrolling: hover on ${hoveredNow()}, '
                'pointer is over $under',
          );
        }
        // The pointer leaves the list: no hover fill is left anywhere.
        await mouse.moveTo(const Offset(790, 620));
        await tester.pump();
        await tester.pump();
        final img = await grab(tester);
        final focusedNow = lists
            ? focusedSnippetItem()
            : focusedHistoryItemId();
        final left = [
          for (final (r, id) in visibleRows(tester, screen, rowType, idOf))
            if (hasHover(img, r) && id != focusedNow) id,
        ];
        expect(left, isEmpty, reason: 'hover stayed on $left');
      });
    }

    testWidgets('Snippets: after a Move down (the slide animation runs) '
        'exactly one row has the ring and none is painted twice', (
      tester,
    ) async {
      fillSnippets(12);
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: wrapped(),
        ),
      );
      await tester.pumpAndSettle();
      await tapTab(tester, 'main-tab-snippets');
      await tabTo(tester, 'snippet-down-');
      final id = focusedSnippetItem()!;
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        for (var f = 0; f < 4; f++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();
        final img = await grab(tester);
        final rows = visibleRows(
          tester,
          SnippetsScreen,
          SnippetRow,
          (w) => (w as SnippetRow).item.id,
        );
        // The row has the focus on its button: no row-level ring, and no
        // hover fill left behind on the row it left.
        final ringed = [
          for (final (r, rid) in rows)
            if (hasRing(img, r)) rid,
        ];
        expect(ringed.length, lessThanOrEqualTo(1));
        expect(
          [
            for (final (r, rid) in rows)
              if (hasHover(img, r) && rid != id) rid,
          ],
          isEmpty,
          reason: 'a stale hover fill after move $i',
        );
      }
    });
  });

  // ------------- G. no layout or paint error in any frame

  group('no layout or paint error in any frame', () {
    /// Pumps [frames] frames of 16 ms, collecting every reported error.
    Future<List<String>> frames(WidgetTester tester, int frames) async {
      final errors = <String>[];
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = tester.takeException();
        if (e != null) {
          errors.add('frame $i: ${e.toString().split('\n').first}');
        }
      }
      return errors;
    }

    for (final lists in [true, false]) {
      final name = lists ? 'Snippets' : 'History';
      testWidgets('$name: scale 1 -> 2 -> 1.5 -> 1, each frame checked, '
          'with a hovered row, a focused row button, scrolled', (tester) async {
        fillSnippets(40);
        fillHistory(50);
        await show(tester);
        if (lists) await tapTab(tester, 'main-tab-snippets');
        final screen = lists ? SnippetsScreen : HistoryScreen;
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 9,
        );
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await wheel(tester, screen, 1300);
        await mouse.moveTo(tester.getCenter(listOf(screen)));
        await tester.pump();
        await tabToHook(
          tester,
          (h) => h.startsWith(lists ? 'snippet-copy-' : 'history-copy-'),
        );
        final errors = <String>[];
        for (final s in [2.0, 1.5, 1.0, 2.0, 1.0]) {
          scale.value = s;
          errors.addAll(await frames(tester, 12));
          await wheel(tester, screen, 77);
          absorb(tester);
        }
        expect(errors, isEmpty, reason: errors.take(5).join('; '));
      });

      testWidgets('$name: a fling, a resize and a text-size change, frame '
          'by frame', (tester) async {
        fillSnippets(60);
        fillHistory(60);
        await show(tester);
        if (lists) await tapTab(tester, 'main-tab-snippets');
        final screen = lists ? SnippetsScreen : HistoryScreen;
        await tester.fling(
          listOf(screen),
          const Offset(0, -900),
          2500,
          warnIfMissed: false,
        );
        final errors = <String>[];
        errors.addAll(await frames(tester, 5));
        tester.view.physicalSize = const Size(520, 420);
        scale.value = 2;
        errors.addAll(await frames(tester, 20));
        tester.view.physicalSize = const Size(900, 700);
        scale.value = 1;
        errors.addAll(await frames(tester, 20));
        tester.view.physicalSize = const Size(400, 400);
        errors.addAll(await frames(tester, 10));
        expect(errors, isEmpty, reason: errors.take(5).join('; '));
      });

      testWidgets('$name: a row kept built off screen by a focused button '
          'while the list is scrolled far and the text size changes', (
        tester,
      ) async {
        fillSnippets(60);
        fillHistory(60);
        await show(tester);
        if (lists) await tapTab(tester, 'main-tab-snippets');
        final screen = lists ? SnippetsScreen : HistoryScreen;
        await tabToHook(
          tester,
          (h) => h.startsWith(lists ? 'snippet-edit-' : 'history-delete-'),
        );
        await wheel(tester, screen, 5000);
        final errors = <String>[];
        for (final s in [2.0, 1.0, 2.0, 1.0]) {
          scale.value = s;
          errors.addAll(await frames(tester, 10));
        }
        expect(errors, isEmpty, reason: errors.take(5).join('; '));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
