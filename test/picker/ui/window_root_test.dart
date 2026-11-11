import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';

import '../../support/fakes.dart';
import '../fake_picker_port.dart';
import '../../support/main_tabs.dart';

void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController controller;

  setUp(() {
    port = FakePickerPort();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
  });

  Future<void> pumpApp(WidgetTester tester, {bool historyReady = true}) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    await controller.start();
    if (historyReady) await controller.attach(history);
    await tester.pumpWidget(
      KusungaApp(history: Future.value(history), picker: controller),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('manage mode is the history screen with the picker settings', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('History'), findsNWidgets(2)); // tab and heading
    // The shortcut row is in the Settings tab since M1.7 (D1 A).
    expect(find.text('Picker shortcut: ⇧⌘V'), findsNothing);
    expect(find.text('Search history…'), findsNothing);
    await tester.tap(mainTab('main-tab-settings'));
    await tester.pump();
    expect(find.text('Picker shortcut: ⇧⌘V'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('the shortcut shows the picker, Esc brings the history back', (
    tester,
  ) async {
    source.copy('hello there');
    await pumpApp(tester);
    port.press();
    await tester.pump();
    await tester.pump();
    expect(find.text('Search history…'), findsOneWidget);
    expect(find.text('hello there'), findsOneWidget);
    // The history screen (its footer) is hidden; the picker has its own
    // "History" tab now (M1.4).
    expect(find.text('1 of 200 items'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('Search history…'), findsNothing);
    expect(find.text('1 of 200 items'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('losing focus puts the history screen back', (tester) async {
    await pumpApp(tester);
    port.press();
    await tester.pump();
    port.dismiss();
    await tester.pump();
    await tester.pump();
    expect(find.text('History'), findsNWidgets(2)); // tab and heading
    controller.dispose();
  });

  testWidgets('a paste that could not press the keys shows the toast, then '
      'the history screen after 4 seconds', (tester) async {
    source.copy('hello there');
    await pumpApp(tester);
    port.press();
    await tester.pump();
    await tester.pump();
    port.pasteAnswer = PasteOutcome.focusTimeout;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Copied — press ⌘V to paste.'), findsOneWidget);
    expect(find.text('Search history…'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Copied — press ⌘V to paste.'), findsNothing);
    expect(find.text('History'), findsNWidgets(2)); // tab and heading
    controller.dispose();
  });

  testWidgets('a successful paste goes back to the history screen', (
    tester,
  ) async {
    source.copy('hello there');
    await pumpApp(tester);
    port.press();
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(port.pastes.single.text, 'hello there');
    expect(find.text('History'), findsNWidgets(2)); // tab and heading
    controller.dispose();
  });

  testWidgets('the picker opens while the history is still opening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    await controller.start();
    port.press();
    await tester.pumpWidget(
      KusungaApp(
        history: Future<HistoryService>.delayed(
          const Duration(seconds: 30),
          () => history,
        ),
        picker: controller,
      ),
    );
    await tester.pump();
    expect(find.text('Opening your history…'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump(const Duration(seconds: 31));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the hidden history screen never overflows at the picker and '
        'toast sizes, text x$scale (L1)', (tester) async {
      source.copy('item');
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpApp(tester);
      port.press();
      tester.view.physicalSize = const Size(360, 240);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'picker size');
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await controller.pasteItem(history.items.first.id);
      tester.view.physicalSize = const Size(360, 96);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'toast size');
      // Native puts the window back to its size when the toast goes.
      tester.view.physicalSize = const Size(800, 632);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      controller.dispose();
    });
  }

  testWidgets('the search field has the focus when the picker opens, although '
      'a history row had it (B1)', (tester) async {
    source.copy('row one');
    source.copy('row two');
    await pumpApp(tester);
    // The first history row has the focus (autofocus), as in the real app.
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    port.press();
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    controller.dispose();
  });

  testWidgets('without a picker controller the app is just the history', (
    tester,
  ) async {
    await tester.pumpWidget(KusungaApp(history: Future.value(history)));
    await tester.pump();
    await tester.pump();
    expect(find.text('History'), findsNWidgets(2)); // tab and heading
    expect(find.textContaining('Picker shortcut'), findsNothing);
  });
}
