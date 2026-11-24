import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/ui/picker_panel.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../fake_picker_port.dart';

/// WCAG 2.4.11 in the picker (checked with the History fix, PM decision
/// 2026-11-05): Up/Down, Home/End keep the selected row on screen. The
/// picker's rows have one fixed height, so it scrolls by index.
void main() {
  late FakePickerPort port;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController controller;

  setUp(() {
    port = FakePickerPort();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore()..setLimit(5000),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
  });

  Future<void> show(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(560, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    addTearDown(controller.dispose);
    await controller.start();
    await controller.attach(history);
    port.press();
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: PickerPanel(controller: controller),
      ),
    );
    await tester.pump();
  }

  /// The ▶ marker of the selected row lies inside the list's viewport.
  void expectSelectionOnScreen(WidgetTester tester, String reason) {
    final marker = find.text('▶');
    expect(marker, findsOneWidget, reason: '$reason: a row is selected');
    final row = tester.getRect(marker);
    final view = tester.getRect(find.byType(Scrollable).last);
    expect(
      row.top >= view.top - 0.5 && row.bottom <= view.bottom + 0.5,
      isTrue,
      reason: '$reason: $row is not inside $view',
    );
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  for (final scale in [1.0, 2.0]) {
    for (final n in [60, 400, 5000]) {
      testWidgets('${(scale * 100).toInt()}%, $n items: Down, Up, End, Home '
          'keep the selected row on screen', (tester) async {
        for (var i = 0; i < n; i++) {
          source.copy(i % 3 == 0 ? 'item $i\nsecond line' : 'item $i');
        }
        await show(tester, textScale: scale);
        for (var i = 1; i <= 30; i++) {
          await key(tester, LogicalKeyboardKey.arrowDown);
          expectSelectionOnScreen(tester, 'Down #$i');
        }
        for (var i = 1; i <= 30; i++) {
          await key(tester, LogicalKeyboardKey.arrowUp);
          expectSelectionOnScreen(tester, 'Up #$i');
        }
        await key(tester, LogicalKeyboardKey.end);
        expectSelectionOnScreen(tester, 'End');
        for (var i = 1; i <= 12; i++) {
          await key(tester, LogicalKeyboardKey.arrowUp);
          expectSelectionOnScreen(tester, 'Up #$i after End');
        }
        await key(tester, LogicalKeyboardKey.home);
        expectSelectionOnScreen(tester, 'Home');
        // Let the background indexing and the announcement timers finish.
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
