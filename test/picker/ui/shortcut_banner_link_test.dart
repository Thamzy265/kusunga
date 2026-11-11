// M1.7 reviewer F9 (PM decision 2026-11-11, "Add a link"): the History
// banner for a taken picker shortcut has a text button "Change in Settings"
// that opens the Settings tab with the focus on Change.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/ui/picker_settings_section.dart';
import 'package:kusunga/picker/ui/window_root.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../fake_picker_port.dart';

void main() {
  late FakePickerPort port;
  late HistoryService history;
  late PickerController controller;

  const banner =
      "Kusunga's shortcut ⇧⌘V is used by another app. Choose another.";

  setUp(() {
    port = FakePickerPort()..registerAnswer = (_) => ShortcutRegistration.taken;
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
  });

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  /// The primary focus is on [finder]'s widget or inside it.
  bool hasFocus(WidgetTester tester, Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused is! Element || finder.evaluate().isEmpty) return false;
    final target = tester.element(finder);
    if (focused == target) return true;
    var found = false;
    focused.visitAncestorElements((e) {
      if (e == target) found = true;
      return !found;
    });
    return found;
  }

  Future<void> showWindow(WidgetTester tester) async {
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(history);
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: WindowRoot(history: Future.value(history), picker: controller),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder link() => find.descendant(
    of: hook('shortcut-banner-change'),
    matching: find.byType(TextButton),
  );

  Finder change() => find.descendant(
    of: hook('shortcut-change'),
    matching: find.byType(OutlinedButton),
  );

  testWidgets('the banner in History has "Change in Settings"; it opens '
      'Settings with the focus on Change', (tester) async {
    await showWindow(tester);
    expect(find.text(banner), findsOneWidget);
    expect(find.text('Change in Settings'), findsOneWidget);
    expect(change().hitTestable(), findsNothing, reason: 'Settings is hidden');
    await tester.tap(link());
    await tester.pumpAndSettle();
    expect(change().hitTestable(), findsOneWidget, reason: 'Settings shows');
    expect(hasFocus(tester, change()), isTrue);
  });

  testWidgets('by keyboard: Enter on the link does the same', (tester) async {
    await showWindow(tester);
    for (var i = 0; i < 20 && !hasFocus(tester, link()); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(hasFocus(tester, link()), isTrue, reason: 'Tab reaches the link');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(hasFocus(tester, change()), isTrue);
  });

  testWidgets('its accessible name is "Change in Settings"', (tester) async {
    final handle = tester.ensureSemantics();
    await showWindow(tester);
    expect(find.bySemanticsLabel('Change in Settings'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('no link where Change is right there (everything in one '
      'place), and none without the banner', (tester) async {
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    addTearDown(controller.dispose);
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PickerSettingsSection(controller: controller),
          ),
        ),
      ),
    );
    expect(find.text(banner), findsOneWidget);
    expect(find.text('Change in Settings'), findsNothing);

    port.registerAnswer = (_) => ShortcutRegistration.registered;
    final free = FakePickerPort();
    final ok = PickerController(port: free, log: FakeLog(), isMac: true);
    addTearDown(ok.dispose);
    await ok.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: Scaffold(
          body: PickerSettingsSection(
            controller: ok,
            parts: PickerSettingsParts.notices,
          ),
        ),
      ),
    );
    expect(find.text('Change in Settings'), findsNothing);
  });
}
