// M1.7 (D1 A): the picker shortcut row moved to the Settings tab; the
// shortcut-taken banner and the Mac permission card stay in History.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/ui/picker_settings_section.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../fake_picker_port.dart';

void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController controller;

  setUp(() {
    port = FakePickerPort()..registerAnswer = (_) => ShortcutRegistration.taken;
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
  });

  Future<void> show(WidgetTester tester, PickerSettingsParts parts) async {
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(history);
    source.copy('x');
    port.press();
    port.pasteAnswer = PasteOutcome.noPermission;
    await controller.pasteItem(history.items.single.id);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PickerSettingsSection(controller: controller, parts: parts),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const banner =
      "Kusunga's shortcut ⇧⌘V is used by another app. Choose another.";

  testWidgets('notices: the banner and the card, no shortcut row', (
    tester,
  ) async {
    await show(tester, PickerSettingsParts.notices);
    expect(find.text(banner), findsOneWidget);
    expect(find.text('Let Kusunga paste for you'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    expect(find.textContaining('Picker shortcut:'), findsNothing);
    await tester.pump(const Duration(seconds: 10)); // the paste's timers
  });

  testWidgets('shortcut: the row with Change, no banner or card', (
    tester,
  ) async {
    await show(tester, PickerSettingsParts.shortcut);
    expect(find.text('Picker shortcut: ⇧⌘V'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text(banner), findsNothing);
    expect(find.text('Let Kusunga paste for you'), findsNothing);
    await tester.pump(const Duration(seconds: 10)); // the paste's timers
  });

  testWidgets('all (the default): everything, as before M1.7', (tester) async {
    await show(tester, PickerSettingsParts.all);
    expect(find.text(banner), findsOneWidget);
    expect(find.text('Let Kusunga paste for you'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10)); // the paste's timers
  });
}
