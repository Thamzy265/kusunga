// Tester probes: what the user loses when the picker replaces the history
// screen and gives it back (the one window is rebuilt).
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';

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

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(history);
    await tester.pumpWidget(
      KusungaApp(history: Future.value(history), picker: controller),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openAndCloseThePicker(WidgetTester tester) async {
    port.press();
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a delete that can still be undone can still be undone after '
      'a trip to the picker', (tester) async {
    // BUG-U1: the history screen (and its snackbar) is rebuilt, so "Undo"
    // disappears and the deleted item is lost for good, although the 5
    // second Undo window had not run out.
    source.copy('precious text');
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsOneWidget);
    expect(history.items, isEmpty);

    await openAndCloseThePicker(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Undo'), findsOneWidget, reason: 'Undo went away');
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect([for (final i in history.items) i.preview], ['precious text']);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Undo with the keyboard (Cmd+Z) also survives the trip', (
    tester,
  ) async {
    // BUG-U1, keyboard form.
    // With only one item the focus is lost by the delete itself (also without
    // a trip), so there is an older item whose row takes the focus.
    source.copy('older text');
    source.copy('precious text');
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
    await tester.pump();
    await openAndCloseThePicker(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(
      [for (final i in history.items) i.preview],
      ['precious text', 'older text'],
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the scroll position of a long history survives the trip', (
    tester,
  ) async {
    // BUG-U2 (low): the list starts again at the top.
    for (var i = 0; i < 80; i++) {
      source.copy('item number $i');
    }
    await pumpApp(tester);
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -1500));
    await tester.pump();
    double offset() => tester.state<ScrollableState>(list).position.pixels;
    final before = offset();
    expect(before, greaterThan(500));

    await openAndCloseThePicker(tester);

    expect(offset(), before);
  });

  testWidgets('an unfinished limit edit never saves a half-typed number', (
    tester,
  ) async {
    // Regression lock: typing "5" on the way to "500" and being interrupted by
    // the picker must not set the limit to 5 (below the 10 minimum) or to 5.
    await pumpApp(tester);
    await showKeepField(tester); // in Settings since M1.7
    final field = find.byKey(const Key('limit-field'));
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, '5');
    await tester.pump();
    await openAndCloseThePicker(tester);
    expect(history.limit, 200);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('copies made while the picker shows are in the history after', (
    tester,
  ) async {
    await pumpApp(tester);
    port.press();
    await tester.pump();
    source.copy('copied while open');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('copied while open'), findsOneWidget);
  });
}
