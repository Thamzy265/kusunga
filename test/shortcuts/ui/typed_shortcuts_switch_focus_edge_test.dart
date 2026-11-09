// Tester edge cases for the Typed shortcuts switch focus ring (QA-M15-1):
// hidden on mouse focus, back on the next key, against the real page
// background, at 360 px and 200% text, after the section is gone, and for a
// switch that is disabled.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/ui/typed_shortcuts_section.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../../theme/tokens_test.dart' show contrast;
import '../fake_typed_shortcuts_port.dart';

void main() {
  late ShortcutService service;

  Future<KusungaTokens> show(
    WidgetTester tester,
    Brightness brightness, {
    bool reduceMotion = false,
    bool available = true,
    double width = 800,
    double textScale = 1,
  }) async {
    final settings = {'typed_shortcuts_on': '0'};
    service = ShortcutService(
      port: FakeTypedShortcutsPort(),
      snippets: SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      ),
      ignoredApps: MemoryIgnoredAppStore(),
      readSetting: (k) => settings[k],
      writeSetting: (k, v) {
        settings[k] = v;
        return true;
      },
      log: FakeLog(),
      isWindows: false,
      available: available,
    );
    addTearDown(service.dispose);
    await tester.runAsync(service.start);
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: TypedShortcutsSection(service: service, isMac: true),
          ),
        ),
      ),
    );
    await tester.pump();
    return KusungaTokens.of(tester.element(find.byType(TypedShortcutsSection)));
  }

  final switchFinder = find.byKey(const ValueKey('typed-shortcuts-switch'));
  final ringFinder = find.byKey(const ValueKey('typed-shortcuts-switch-ring'));

  FocusNode node(WidgetTester tester) =>
      tester.widget<Switch>(switchFinder).focusNode!;

  Color ring(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(ringFinder);
    return ((box.decoration as BoxDecoration).border! as Border).top.color;
  }

  bool showing(WidgetTester tester, KusungaTokens t) => ring(tester) == t.focus;

  Future<void> tab(WidgetTester tester) async {
    for (var i = 0; i < 10 && !node(tester).hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(node(tester).hasFocus, isTrue);
  }

  setUp(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  for (final brightness in Brightness.values) {
    group('${brightness.name}:', () {
      testWidgets('a mouse click gives the switch focus but no ring; the next '
          'key brings the ring back', (tester) async {
        final t = await show(tester, brightness);
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();
        // A click does not move the focus itself; give it to the switch the
        // way a click on its label would, while still in touch mode.
        node(tester).requestFocus();
        await tester.pump();
        expect(node(tester).hasFocus, isTrue);
        expect(
          FocusManager.instance.highlightMode,
          FocusHighlightMode.touch,
          reason: 'a pointer event is touch mode',
        );
        expect(showing(tester, t), isFalse, reason: 'no ring on mouse focus');
        await tester.sendKeyEvent(LogicalKeyboardKey.shift);
        await tester.pump();
        expect(
          FocusManager.instance.highlightMode,
          FocusHighlightMode.traditional,
        );
        expect(showing(tester, t), isTrue, reason: 'a key: the ring returns');
        // Clicking again hides it again, while the switch keeps the focus.
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();
        expect(node(tester).hasFocus, isTrue);
        expect(showing(tester, t), isFalse);
      });

      testWidgets('the ring follows the highlight strategy even without a '
          'focus change', (tester) async {
        final t = await show(tester, brightness);
        await tab(tester);
        expect(showing(tester, t), isTrue);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        await tester.pump();
        expect(showing(tester, t), isFalse);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        await tester.pump();
        expect(showing(tester, t), isTrue);
      });

      testWidgets('with reduce motion on the ring survives the switch being '
          'rebuilt for each value (toggle by key, twice)', (tester) async {
        final t = await show(tester, brightness, reduceMotion: true);
        await tab(tester);
        for (var i = 0; i < 2; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(node(tester).hasFocus, isTrue, reason: 'toggle ${i + 1}');
          expect(showing(tester, t), isTrue, reason: 'toggle ${i + 1}');
        }
        expect(service.enabled, isFalse);
      });

      testWidgets('3:1 against the real page background, not only the '
          'surface', (tester) async {
        final t = await show(tester, brightness);
        await tab(tester);
        final bg = Theme.of(tester.element(ringFinder)).scaffoldBackgroundColor;
        expect(contrast(t.focus, bg), greaterThanOrEqualTo(3));
        expect(contrast(t.focus, t.surface), greaterThanOrEqualTo(3));
      });

      testWidgets('at 360 px and 200% text the ring is complete, on screen, '
          'and nothing overflows', (tester) async {
        final t = await show(tester, brightness, width: 360, textScale: 2);
        await tab(tester);
        expect(showing(tester, t), isTrue);
        final r = tester.getRect(ringFinder);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        final s = tester.getRect(switchFinder);
        expect(r.width, greaterThanOrEqualTo(s.width));
        expect(s.width, greaterThanOrEqualTo(40));
        expect(s.height, greaterThanOrEqualTo(24));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a disabled switch cannot be focused, so it never shows the '
          'ring', (tester) async {
        final t = await show(tester, brightness, available: false);
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(node(tester).hasFocus, isFalse);
        expect(showing(tester, t), isFalse);
      });
    });
  }

  testWidgets('the ring does not change the switch size or position when it '
      'appears', (tester) async {
    final t = await show(tester, Brightness.light);
    final before = tester.getRect(switchFinder);
    final ringBefore = tester.getRect(ringFinder);
    await tab(tester);
    expect(showing(tester, t), isTrue);
    expect(tester.getRect(switchFinder), before);
    expect(tester.getRect(ringFinder), ringBefore);
  });

  testWidgets('after the section is gone, a highlight change does not throw '
      '(the listener was removed)', (tester) async {
    await show(tester, Brightness.light);
    await tab(tester);
    await tester.pumpWidget(const SizedBox());
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
