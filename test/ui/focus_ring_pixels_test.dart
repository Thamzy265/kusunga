import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_settings_section.dart';
import 'package:kusunga/settings/login_item.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';

import '../picker/fake_picker_port.dart';
import '../snippets/snippet_service_test.dart' show FlakySnippetStore;
import '../support/fakes.dart';
import '../theme/tokens_test.dart' show contrast;
import '../support/main_tabs.dart';

/// Tester probes for QA-M14-4 (c0dbfe0), on what is really drawn: the 2 px
/// `color.focus` ring is painted on all four sides of every control on both
/// tabs, in the editor and in the dialogs (not clipped by a row, a card or
/// the window edge), and the pixels right outside it are at least 3:1 from
/// the ring (WCAG 1.4.11), in light and dark. The widget-level checks are in
/// focus_ring_test.dart; these read the rendered pixels.
void main() {
  late FakeClipboardSource source;
  late HistoryService service;
  late FlakySnippetStore snippetStore;
  final boundary = GlobalKey();

  setUp(() {
    source = FakeClipboardSource();
    snippetStore = FlakySnippetStore();
  });

  Future<KusungaTokens> show(
    WidgetTester tester,
    Brightness brightness, {
    Size size = const Size(800, 632),
    double textScale = 1,
    Set<HistoryNotice> notices = const {},
    Widget? home,
  }) async {
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      snippetStore: snippetStore,
      notices: notices,
      writeClipboard: (_) async {},
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
        home: home ?? HistoryHost(history: Future.value(service)),
      ),
    );
    await tester.pump();
    await tester.pump();
    return brightness == Brightness.dark
        ? KusungaTokens.dark
        : KusungaTokens.light;
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  bool hasFocus(WidgetTester tester, Finder control) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final target = tester.element(control);
    var found = false;
    focused.visitAncestorElements((e) {
      if (e == target) found = true;
      return !found;
    });
    return found || focused == target;
  }

  Future<void> tabTo(WidgetTester tester, Finder control) async {
    for (var i = 0; i < 40 && !hasFocus(tester, control); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(hasFocus(tester, control), isTrue, reason: 'Tab reaches it');
    await tester.pump(const Duration(milliseconds: 300));
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

  bool isRing(Color c, Color ring) =>
      (c.toARGB32() >> 16 & 255) - (ring.toARGB32() >> 16 & 255) <= 6 &&
      (c.toARGB32() >> 16 & 255) - (ring.toARGB32() >> 16 & 255) >= -6 &&
      (c.toARGB32() >> 8 & 255) - (ring.toARGB32() >> 8 & 255) <= 6 &&
      (c.toARGB32() >> 8 & 255) - (ring.toARGB32() >> 8 & 255) >= -6 &&
      (c.toARGB32() & 255) - (ring.toARGB32() & 255) <= 6 &&
      (c.toARGB32() & 255) - (ring.toARGB32() & 255) >= -6;

  /// The control, focused by Tab, shows the ring on all four sides: a pixel
  /// of exactly the ring colour within 3 px of each edge midpoint, and the
  /// pixel 5 px outside that edge is 3:1 from the ring.
  Future<void> expectRing(
    WidgetTester tester,
    Finder control,
    KusungaTokens t,
    String what, {
    bool tab = true,
  }) async {
    if (tab) await tabTo(tester, control);
    await tester.pump(const Duration(milliseconds: 300));
    final img = await grab(tester);
    // The button's own Material (an IconButton's tap target is larger than
    // what is drawn); fields and the Type menu have none of their own.
    final materials = find.descendant(
      of: control,
      matching: find.byType(Material),
    );
    final r = tester.getRect(
      materials.evaluate().isEmpty ? control : materials.first,
    );
    final view = Size(img.w.toDouble(), img.h.toDouble());
    final sides = <String, List<(int, int)>>{
      'top': [
        for (var d = -6; d <= 3; d++) (r.center.dx.round(), r.top.round() + d),
      ],
      'bottom': [
        for (var d = -3; d <= 6; d++)
          (r.center.dx.round(), r.bottom.round() + d),
      ],
      'left': [
        for (var d = -6; d <= 3; d++) (r.left.round() + d, r.center.dy.round()),
      ],
      'right': [
        for (var d = -3; d <= 6; d++)
          (r.right.round() + d, r.center.dy.round()),
      ],
    };
    for (final MapEntry(key: side, value: points) in sides.entries) {
      final inside = points
          .where(
            (p) =>
                p.$1 >= 0 &&
                p.$2 >= 0 &&
                p.$1 < view.width &&
                p.$2 < view.height,
          )
          .toList();
      if (inside.isEmpty) continue; // the window edge is the edge of the ring
      expect(
        inside.any((p) => isRing(px(img, p.$1, p.$2), t.focus)),
        isTrue,
        reason: '$what: no ${t.focus} ring pixels at the $side edge $r',
      );
    }
    // Contrast of the ring against what is right outside it.
    final outside = <String, (int, int)>{
      'top': (r.center.dx.round(), r.top.round() - 5),
      'bottom': (r.center.dx.round(), r.bottom.round() + 5),
      'left': (r.left.round() - 5, r.center.dy.round()),
      'right': (r.right.round() + 5, r.center.dy.round()),
    };
    for (final MapEntry(key: side, value: p) in outside.entries) {
      if (p.$1 < 0 || p.$2 < 0 || p.$1 >= view.width || p.$2 >= view.height) {
        continue;
      }
      final bg = px(img, p.$1, p.$2);
      expect(
        contrast(t.focus, bg.withValues(alpha: 1)),
        greaterThanOrEqualTo(3),
        reason: '$what: the ring on the pixel $side of it ($bg)',
      );
    }
  }

  Finder textButton(Finder scope) =>
      find.descendant(of: scope, matching: find.byType(TextButton));

  for (final brightness in Brightness.values) {
    group('${brightness.name}: the ring is drawn on every side', () {
      testWidgets('History tab: More options, row buttons', (tester) async {
        final t = await show(tester, brightness);
        source.copy('first');
        source.copy('second');
        await tester.pump();
        final more = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is PopupMenuButton && w.tooltip == 'More options',
          ),
          matching: find.byType(IconButton),
        );
        await expectRing(tester, more, t, 'More options');
        final id = service.items.first.id;
        for (final (hookId, what) in [
          ('history-copy-$id', 'history Copy'),
          ('history-save-snippet-$id', 'Save as snippet'),
          ('history-delete-$id', 'history Delete'),
        ]) {
          await expectRing(tester, textButton(hook(hookId)), t, what);
        }
      });

      testWidgets('History tab: the limit field and the banner Dismiss', (
        tester,
      ) async {
        final t = await show(
          tester,
          brightness,
          notices: {HistoryNotice.memoryOnly},
        );
        final dismiss = find.widgetWithIcon(IconButton, Icons.close);
        await expectRing(tester, dismiss, t, 'banner Dismiss');
        // The limit field is in the Settings tab since M1.7.
        await showKeepField(tester);
        final field = find.byType(TextField).first;
        await expectRing(tester, field, t, 'limit field');
      });

      testWidgets('Clear history dialog: Cancel and Clear history', (
        tester,
      ) async {
        final t = await show(tester, brightness);
        source.copy('first');
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is PopupMenuButton && w.tooltip == 'More options',
            ),
            matching: find.byType(IconButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear history'));
        await tester.pumpAndSettle();
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        final clear = find.widgetWithText(FilledButton, 'Clear history');
        await expectRing(tester, cancel, t, 'dialog Cancel', tab: false);
        await expectRing(tester, clear, t, 'dialog Clear history');
      });

      testWidgets('Snippets tab: New snippet, the empty-state New snippet', (
        tester,
      ) async {
        final t = await show(tester, brightness);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        await expectRing(
          tester,
          find.descendant(
            of: hook('snippet-new'),
            matching: find.byType(FilledButton),
          ),
          t,
          'New snippet (top)',
        );
        await expectRing(
          tester,
          find.descendant(
            of: hook('snippet-new-empty'),
            matching: find.byType(FilledButton),
          ),
          t,
          'New snippet (empty state)',
        );
      });

      testWidgets('Snippets tab: row buttons, the last one at the row end', (
        tester,
      ) async {
        final t = await show(tester, brightness);
        service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
        service.snippets.save(name: 'B', content: 'b', type: SnippetType.other);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        final id = service.snippets.items.first.id;
        await tester.tap(find.text('A'));
        await tester.pump();
        for (final (hookId, what) in [
          ('snippet-copy-$id', 'Copy'),
          ('snippet-edit-$id', 'Edit'),
          ('snippet-down-$id', 'Move down'),
          ('snippet-delete-$id', 'Delete (right edge of the row)'),
        ]) {
          await expectRing(tester, textButton(hook(hookId)), t, what);
        }
      });

      testWidgets('Snippets tab: More menu button under 600 px', (
        tester,
      ) async {
        final t = await show(tester, brightness, size: const Size(500, 632));
        service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        final id = service.snippets.items.first.id;
        await tester.tap(find.text('A'));
        await tester.pump();
        await expectRing(
          tester,
          find.descendant(
            of: hook('snippet-more-$id'),
            matching: find.byType(IconButton),
          ),
          t,
          'More',
        );
      });

      testWidgets('Snippets tab: Try again in the read-error banner', (
        tester,
      ) async {
        snippetStore.failReads = true;
        final t = await show(tester, brightness);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        await expectRing(
          tester,
          find.widgetWithText(TextButton, 'Try again'),
          t,
          'Try again',
        );
      });

      testWidgets('editor: Name, Type, Content, Cancel, Save, and the '
          'discard dialog', (tester) async {
        final t = await show(tester, brightness);
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: hook('snippet-new'),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        await expectRing(
          tester,
          find.descendant(
            of: hook('snippet-editor-name'),
            matching: find.byType(TextField),
          ),
          t,
          'editor Name',
          tab: false,
        );
        await expectRing(tester, hook('snippet-editor-type'), t, 'Type');
        await expectRing(
          tester,
          find.descendant(
            of: hook('snippet-editor-content'),
            matching: find.byType(TextField),
          ),
          t,
          'editor Content',
        );
        await expectRing(
          tester,
          find.widgetWithText(TextButton, 'Cancel'),
          t,
          'editor Cancel',
        );
        await expectRing(
          tester,
          find.widgetWithText(FilledButton, 'Save'),
          t,
          'editor Save',
        );
        await tester.enterText(find.byType(TextField).first, 'x');
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        await expectRing(
          tester,
          find.widgetWithText(TextButton, 'Keep editing'),
          t,
          'Keep editing',
          tab: false,
        );
        await expectRing(
          tester,
          find.widgetWithText(TextButton, 'Discard'),
          t,
          'Discard',
        );
      });

      testWidgets('editor at 200% text in a small window: Save and Cancel '
          'rings are not clipped', (tester) async {
        final t = await show(
          tester,
          brightness,
          size: const Size(360, 520),
          textScale: 2,
        );
        await tester.tap(hook('main-tab-snippets'));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: hook('snippet-new'),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Save');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        final r = tester.getRect(save);
        expect(r.inflate(3).bottom, lessThanOrEqualTo(520));
        expect(r.inflate(3).right, lessThanOrEqualTo(360));
        await expectRing(tester, save, t, 'Save at 200%');
      });
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: the picker settings buttons show the '
        'ring', (tester) async {
      final port = FakePickerPort();
      final controller = PickerController(
        port: port,
        log: FakeLog(),
        isMac: true,
      );
      addTearDown(controller.dispose);
      await controller.start();
      source = FakeClipboardSource();
      final t = await show(
        tester,
        brightness,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PickerSettingsSection(controller: controller),
          ),
        ),
      );
      await controller.attach(service);
      await tester.pump();
      final change = find.descendant(
        of: hook('shortcut-change'),
        matching: find.byType(OutlinedButton),
      );
      expect(change, findsOneWidget, reason: 'the Change button is shown');
      await expectRing(tester, change, t, 'shortcut Change');
    });
  }

  // M1.7 reviewer F1: the Settings tab's switch and menu had only a faint
  // tint (about 1.1:1) for focus. Added by the developer.
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: the Launch at login switch and the '
        'Auto-delete menu show the ring', (tester) async {
      final login = LoginItemService(port: FakeLoginItemPort(), log: FakeLog());
      addTearDown(login.dispose);
      final opened = Completer<HistoryService>();
      final t = await show(
        tester,
        brightness,
        home: HistoryHost(history: opened.future, loginItem: login),
      );
      opened.complete(service);
      await tester.pump();
      await tester.tap(mainTab('main-tab-settings'));
      await tester.pumpAndSettle();
      final switchRing = find.byKey(
        const ValueKey('settings-launch-at-login-ring'),
      );
      final menuRing = find.byKey(const ValueKey('settings-auto-delete-ring'));
      expect(switchRing, findsOneWidget);
      expect(menuRing, findsOneWidget);
      await expectRing(tester, switchRing, t, 'Launch at login');
      await expectRing(tester, menuRing, t, 'Auto-delete');
    });
  }
}
