import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// BUG-D4: the permission card's heading takes the focus when the card
/// appears, but never from a dialog on top of it (the same rule as the
/// History rows and the Mac setup card). It takes it once the dialog is gone
/// and nothing else has it.
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

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = PickerController(port: port, log: FakeLog(), isMac: true);
    await controller.start();
    await controller.attach(history);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PickerSettingsSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A paste that needs the permission: the card appears.
  Future<void> needPermission(WidgetTester tester) async {
    source.copy('x');
    port.press();
    port.pasteAnswer = PasteOutcome.noPermission;
    await controller.pasteItem(history.items.single.id);
    await tester.pumpAndSettle();
    expect(find.text('Let Kusunga paste for you'), findsOneWidget);
    // The "Copied" toast's own timer.
    await tester.pump(const Duration(seconds: 5));
  }

  String where() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return 'nothing';
    if (ctx.findAncestorWidgetOfExactType<AlertDialog>() != null) {
      return 'dialog';
    }
    final heading = find.descendant(
      of: find.byWidget(ctx.widget),
      matching: find.text('Let Kusunga paste for you'),
    );
    return heading.evaluate().isNotEmpty
        ? 'card heading'
        : 'other(${ctx.widget.runtimeType})';
  }

  testWidgets('with a dialog on top the card appears without taking the '
      'focus; Escape closes the dialog; the heading then has the focus', (
    tester,
  ) async {
    await show(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(PickerSettingsSection)),
        builder: (c) => AlertDialog(
          title: const Text('On top'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(where(), 'dialog');
    await needPermission(tester);
    expect(where(), 'dialog', reason: 'the card took the focus');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('On top'), findsNothing, reason: 'Escape');
    expect(where(), 'card heading');
  });

  testWidgets('with no dialog the heading takes the focus when the card '
      'appears (the original behaviour)', (tester) async {
    await show(tester);
    await needPermission(tester);
    expect(where(), 'card heading');
  });
}
