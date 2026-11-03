import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show Assertiveness;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/ui/picker_toast.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../fake_picker_port.dart';

void main() {
  late FakePickerPort port;
  late PickerController controller;
  late HistoryService history;
  late FakeClipboardSource source;

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

  Future<void> showToast(
    WidgetTester tester,
    PasteOutcome outcome, {
    bool isMac = true,
    Size size = const Size(360, 96),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    controller = PickerController(port: port, log: FakeLog(), isMac: isMac);
    await controller.start();
    await controller.attach(history);
    source.copy('x');
    port.press();
    port.pasteAnswer = outcome;
    await controller.pasteItem(history.items.single.id);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        home: PickerToastView(controller: controller),
      ),
    );
    await tester.pump();
    addTearDown(controller.dispose);
  }

  testWidgets('shows the copied message', (tester) async {
    await showToast(tester, PasteOutcome.focusTimeout);
    expect(find.text('Copied — press ⌘V to paste.'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('says how to allow pasting when the permission is missing', (
    tester,
  ) async {
    await showToast(tester, PasteOutcome.noPermission);
    expect(
      find.text(
        'Copied — press ⌘V to paste. Allow pasting in Kusunga to do this for you.',
      ),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('Windows administrator message', (tester) async {
    await showToast(tester, PasteOutcome.targetElevated, isMac: false);
    expect(
      find.text(
        "Copied — press Ctrl+V to paste. Kusunga can't paste into apps run as administrator.",
      ),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('it is a live region, announced assertively once', (
    tester,
  ) async {
    final announcements = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        announcements.add(message as Map<Object?, Object?>);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    final handle = tester.ensureSemantics();
    await showToast(tester, PasteOutcome.focusTimeout);
    await tester.pump();
    final node = tester.getSemantics(
      find.byKey(const ValueKey('picker-toast')),
    );
    expect(node.label, 'Copied — press ⌘V to paste.');
    expect(node.flagsCollection.isLiveRegion, isTrue);
    final spoken = announcements.where((m) => m['type'] == 'announce').toList();
    expect(spoken.length, 1);
    final data = spoken.single['data'] as Map<Object?, Object?>;
    expect(data['message'], 'Copied — press ⌘V to paste.');
    expect(data['assertiveness'], Assertiveness.assertive.index);
    handle.dispose();
    controller.dispose();
  });

  testWidgets('long messages fit the toast window at 200% text', (
    tester,
  ) async {
    await showToast(
      tester,
      PasteOutcome.targetElevated,
      isMac: false,
      textScale: 2,
      size: const Size(360, 160),
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  for (final b in Brightness.values) {
    testWidgets('contrast, ${b.name}', (tester) async {
      final handle = tester.ensureSemantics();
      await showToast(tester, PasteOutcome.noPermission, brightness: b);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      controller.dispose();
    });
  }
}
