// QA-M15-1 (WCAG 2.4.7, 1.4.11): the Typed shortcuts switch shows the same
// 2 px `color.focus` ring as the buttons, chips and tabs when it has the
// keyboard focus, drawn outside it on the background at 3:1 or more, in
// light and dark. Material's own focus halo is about 1.25:1.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
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
  final boundary = GlobalKey();

  Future<KusungaTokens> show(
    WidgetTester tester,
    Brightness brightness, {
    bool reduceMotion = false,
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
      available: true,
    );
    addTearDown(service.dispose);
    await tester.runAsync(service.start);
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            // Room around it, as on the Snippets tab, so every side of the
            // ring is on screen.
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TypedShortcutsSection(service: service, isMac: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return brightness == Brightness.dark
        ? KusungaTokens.dark
        : KusungaTokens.light;
  }

  final switchFinder = find.byKey(const ValueKey('typed-shortcuts-switch'));
  final ringFinder = find.byKey(const ValueKey('typed-shortcuts-switch-ring'));

  FocusNode switchNode(WidgetTester tester) =>
      tester.widget<Switch>(switchFinder).focusNode!;

  Future<void> tabToSwitch(WidgetTester tester) async {
    for (var i = 0; i < 10 && !switchNode(tester).hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(switchNode(tester).hasFocus, isTrue, reason: 'Tab reaches it');
  }

  BorderSide ringSide(WidgetTester tester) {
    expect(ringFinder, findsOneWidget, reason: 'the ring wraps the switch');
    expect(
      find.descendant(of: ringFinder, matching: switchFinder),
      findsOneWidget,
    );
    final box = tester.widget<DecoratedBox>(ringFinder);
    final border = (box.decoration as BoxDecoration).border! as Border;
    return border.top;
  }

  Future<({ByteData data, int w, int h})> grab(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final data = (await image.toByteData())!;
      return (data: data, w: image.width, h: image.height);
    }))!;
  }

  Color px(({ByteData data, int w, int h}) img, int x, int y) {
    final o = (y * img.w + x) * 4;
    return Color.fromARGB(
      img.data.getUint8(o + 3),
      img.data.getUint8(o),
      img.data.getUint8(o + 1),
      img.data.getUint8(o + 2),
    );
  }

  bool near(Color a, Color b) {
    int ch(Color c, int shift) => c.toARGB32() >> shift & 255;
    return [16, 8, 0].every((s) => (ch(a, s) - ch(b, s)).abs() <= 6);
  }

  for (final brightness in Brightness.values) {
    group('${brightness.name}:', () {
      testWidgets('pixels: the focus colour is drawn on all four sides of the '
          'focused switch, and is 3:1 on what is right outside it', (
        tester,
      ) async {
        final t = await show(tester, brightness);
        await tabToSwitch(tester);
        await tester.pump(const Duration(milliseconds: 300));
        final img = await grab(tester);
        final r = tester.getRect(switchFinder);
        final sides = <String, List<(int, int)>>{
          'top': [
            for (var d = -4; d <= 1; d++)
              (r.center.dx.round(), r.top.round() + d),
          ],
          'bottom': [
            for (var d = -2; d <= 3; d++)
              (r.center.dx.round(), r.bottom.round() + d),
          ],
          'left': [
            for (var d = -4; d <= 1; d++)
              (r.left.round() + d, r.center.dy.round()),
          ],
          'right': [
            for (var d = -2; d <= 3; d++)
              (r.right.round() + d, r.center.dy.round()),
          ],
        };
        for (final MapEntry(key: side, value: points) in sides.entries) {
          expect(
            points.any((p) => near(px(img, p.$1, p.$2), t.focus)),
            isTrue,
            reason: 'no ${t.focus} ring pixels at the $side edge of $r',
          );
        }
        final outside = px(img, r.left.round() - 6, r.center.dy.round());
        expect(contrast(t.focus, outside), greaterThanOrEqualTo(3));
      });

      testWidgets('keyboard focus draws the 2 px focus ring outside the '
          'switch, 3:1 on the background', (tester) async {
        final t = await show(tester, brightness);
        expect(ringSide(tester).color, isNot(t.focus), reason: 'not focused');
        await tabToSwitch(tester);
        final side = ringSide(tester);
        expect(side.color, t.focus);
        expect(side.width, greaterThanOrEqualTo(2));
        expect(side.strokeAlign, BorderSide.strokeAlignOutside);
        expect(contrast(side.color, t.surface), greaterThanOrEqualTo(3));
      });

      testWidgets('the ring stays while the switch is toggled with Space, '
          'with reduce motion on', (tester) async {
        final t = await show(tester, brightness, reduceMotion: true);
        await tabToSwitch(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(service.enabled, isTrue);
        expect(switchNode(tester).hasFocus, isTrue);
        expect(ringSide(tester).color, t.focus);
      });

      testWidgets('the ring goes when the focus leaves', (tester) async {
        final t = await show(tester, brightness);
        await tabToSwitch(tester);
        switchNode(tester).unfocus();
        await tester.pump();
        expect(ringSide(tester).color, isNot(t.focus));
      });
    });
  }
}
