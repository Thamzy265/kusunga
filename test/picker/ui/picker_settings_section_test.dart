import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
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
    port = FakePickerPort();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: const NullErrorLog(),
    )..start();
    addTearDown(history.dispose);
  });

  Future<void> show(
    WidgetTester tester, {
    bool isMac = true,
    Size size = const Size(800, 632),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    bool start = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    controller = PickerController(port: port, log: FakeLog(), isMac: isMac);
    if (start) {
      await controller.start();
      await controller.attach(history);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PickerSettingsSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(controller.dispose);
  }

  Finder byId(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> record(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> held = const [],
  }) async {
    for (final m in held) {
      await tester.sendKeyDownEvent(m);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    for (final m in held.reversed) {
      await tester.sendKeyUpEvent(m);
    }
    await tester.pump();
  }

  Future<void> startRecording(WidgetTester tester) async {
    await tester.tap(find.text('Change'));
    await tester.pump();
  }

  group('shortcut setting', () {
    testWidgets('shows the shortcut and a Change button (Mac)', (tester) async {
      await show(tester);
      expect(find.text('Picker shortcut: ⇧⌘V'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(byId('shortcut-change'), findsOneWidget);
    });

    testWidgets('Windows shows the names', (tester) async {
      await show(tester, isMac: false);
      expect(find.text('Picker shortcut: Ctrl+Shift+V'), findsOneWidget);
    });

    testWidgets('Change starts recording: the shortcut is released', (
      tester,
    ) async {
      await show(tester);
      await startRecording(tester);
      expect(find.text('Press the new shortcut…'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      expect(port.calls.last, 'unregister');
    });

    testWidgets('a free combination is saved and shown', (tester) async {
      await show(tester);
      await startRecording(tester);
      await record(
        tester,
        LogicalKeyboardKey.keyK,
        held: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft],
      );
      expect(find.text('Shortcut saved'), findsOneWidget);
      expect(find.text('Picker shortcut: ⇧⌘K'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(history.setting('picker_shortcut'), 'shift+meta+k');
    });

    testWidgets('a taken combination is explained; the old one stays', (
      tester,
    ) async {
      await show(tester);
      port.registerAnswer = (_) => ShortcutRegistration.taken;
      await startRecording(tester);
      await record(
        tester,
        LogicalKeyboardKey.keyK,
        held: [LogicalKeyboardKey.metaLeft],
      );
      expect(
        find.text('That shortcut is used by another app. Choose another.'),
        findsOneWidget,
      );
      expect(find.text('Picker shortcut: ⇧⌘V'), findsOneWidget);
      expect(port.calls.last, 'register shift+meta+v');
    });

    testWidgets('no Cmd, Ctrl or Alt: explains and keeps listening', (
      tester,
    ) async {
      await show(tester);
      await startRecording(tester);
      await record(tester, LogicalKeyboardKey.keyK);
      expect(
        find.text('Use at least one of ⌘, ⌃ or ⌥ with a key.'),
        findsOneWidget,
      );
      expect(find.text('Press the new shortcut…'), findsOneWidget);
    });

    testWidgets('Cmd+V is refused with the copy-and-paste message', (
      tester,
    ) async {
      await show(tester);
      await startRecording(tester);
      await record(
        tester,
        LogicalKeyboardKey.keyV,
        held: [LogicalKeyboardKey.metaLeft],
      );
      expect(
        find.text(
          'That shortcut is needed for copy and paste. Choose another.',
        ),
        findsOneWidget,
      );
      expect(find.text('Picker shortcut: ⇧⌘V'), findsOneWidget);
      expect(find.text('Press the new shortcut…'), findsOneWidget);
    });

    testWidgets('Windows wording for the same problem', (tester) async {
      await show(tester, isMac: false);
      await startRecording(tester);
      await record(tester, LogicalKeyboardKey.keyK);
      expect(
        find.text('Use at least one of Ctrl, Alt or Win with a key.'),
        findsOneWidget,
      );
    });

    testWidgets('a modifier on its own does nothing', (tester) async {
      await show(tester);
      await startRecording(tester);
      await record(tester, LogicalKeyboardKey.metaLeft);
      expect(find.text('Press the new shortcut…'), findsOneWidget);
      expect(find.textContaining('Use at least'), findsNothing);
    });

    testWidgets('Esc cancels and puts the old shortcut back', (tester) async {
      await show(tester);
      await startRecording(tester);
      await record(tester, LogicalKeyboardKey.escape);
      expect(find.text('Change'), findsOneWidget);
      expect(port.calls.last, 'register shift+meta+v');
      expect(history.setting('picker_shortcut'), isNull);
    });

    testWidgets('the recorder has the focus even if a button had it', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('Change'));
      await tester.pump();
      await tester.pump();
      final ctx = FocusManager.instance.primaryFocus?.context;
      expect(ctx, isNotNull);
      expect(
        find.descendant(
          of: find.byWidget(ctx!.widget),
          matching: find.text('Press the new shortcut…'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the window losing focus cancels recording (B3)', (
      tester,
    ) async {
      await show(tester);
      await startRecording(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Change'), findsOneWidget);
      expect(port.calls.last, 'register shift+meta+v');
    });

    testWidgets('recording that gets no key gives up after 20 seconds (B3)', (
      tester,
    ) async {
      await show(tester);
      await startRecording(tester);
      await tester.pump(const Duration(seconds: 19));
      expect(find.text('Press the new shortcut…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Change'), findsOneWidget);
      expect(port.calls.last, 'register shift+meta+v');
      expect(find.text('Shortcut not changed.'), findsOneWidget);
    });

    testWidgets('every key attempt, refused ones too, restarts the 20 seconds '
        '(T1)', (tester) async {
      await show(tester);
      await startRecording(tester);
      await tester.pump(const Duration(seconds: 15));
      await record(tester, LogicalKeyboardKey.keyK); // refused: no modifier
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('Press the new shortcut…'), findsOneWidget);
      await record(tester, LogicalKeyboardKey.keyK);
      await tester.pump(const Duration(seconds: 19));
      expect(find.text('Press the new shortcut…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Shortcut not changed.'), findsOneWidget);
    });

    testWidgets('"Shortcut not changed." is a polite live region, and Esc '
        'does not show it', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await startRecording(tester);
      await tester.pump(const Duration(seconds: 21));
      final node = tester.getSemantics(find.text('Shortcut not changed.'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
      await startRecording(tester);
      await record(tester, LogicalKeyboardKey.escape);
      expect(find.text('Shortcut not changed.'), findsNothing);
    });

    testWidgets('the card stays hidden at start and after coming back to the '
        'app until a paste needs it (G1)', (tester) async {
      await show(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Let Kusunga paste for you'), findsNothing);
      port.press();
      await controller.closePicker();
      await tester.pump();
      expect(find.text('Let Kusunga paste for you'), findsNothing);
    });

    testWidgets('moving focus away cancels recording', (tester) async {
      await show(tester);
      await startRecording(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Change'), findsOneWidget);
      expect(port.calls.last, 'register shift+meta+v');
    });

    testWidgets('a shortcut that works but could not be saved says so', (
      tester,
    ) async {
      final flaky = FlakyStore(MemoryHistoryStore());
      final h = HistoryService(
        store: flaky,
        source: source,
        log: const NullErrorLog(),
      )..start();
      addTearDown(h.dispose);
      await show(tester, start: false);
      await controller.start();
      await controller.attach(h);
      flaky.failWrites = true;
      await startRecording(tester);
      await record(
        tester,
        LogicalKeyboardKey.keyK,
        held: [LogicalKeyboardKey.controlLeft],
      );
      expect(
        find.text("Couldn't save the shortcut. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('memory-only history: not "saved", the retry text instead', (
      tester,
    ) async {
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: const NullErrorLog(),
        notices: {HistoryNotice.memoryOnly},
      )..start();
      addTearDown(h.dispose);
      await show(tester, start: false);
      await controller.start();
      await controller.attach(h);
      await startRecording(tester);
      await record(
        tester,
        LogicalKeyboardKey.keyK,
        held: [LogicalKeyboardKey.controlLeft],
      );
      expect(find.text('Shortcut saved'), findsNothing);
      expect(
        find.text("Couldn't save the shortcut. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('while recording, keys do not reach anything else', (
      tester,
    ) async {
      await show(tester);
      await startRecording(tester);
      await record(tester, LogicalKeyboardKey.tab);
      expect(find.text('Press the new shortcut…'), findsOneWidget);
    });
  });

  group('banner when the shortcut is taken at start-up', () {
    testWidgets('shows the text and a way to change it', (tester) async {
      port.registerAnswer = (_) => ShortcutRegistration.taken;
      await show(tester);
      expect(
        find.text(
          "Kusunga's shortcut ⇧⌘V is used by another app. Choose another.",
        ),
        findsOneWidget,
      );
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('no banner when it works', (tester) async {
      await show(tester);
      expect(find.textContaining('is used by another app'), findsNothing);
    });
  });

  group('permission card (Mac)', () {
    Future<void> needPermission(WidgetTester tester) async {
      await show(tester);
      source.copy('x');
      port.press();
      port.pasteAnswer = PasteOutcome.noPermission;
      await controller.pasteItem(history.items.single.id);
      await tester.pump();
    }

    testWidgets('hidden until a paste needed the permission', (tester) async {
      await show(tester);
      expect(find.text('Let Kusunga paste for you'), findsNothing);
    });

    testWidgets('shows the heading, the reason and two equal buttons', (
      tester,
    ) async {
      await needPermission(tester);
      expect(find.text('Let Kusunga paste for you'), findsOneWidget);
      expect(
        find.text(
          'To paste into other apps, Kusunga needs permission to send the ⌘V keystroke. It never reads what\'s on your screen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Allow pasting'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(byId('permission-allow'), findsOneWidget);
      expect(byId('permission-not-now'), findsOneWidget);
      final allow = tester.getSize(find.text('Allow pasting'));
      expect(allow.height, greaterThan(0));
      controller.dispose();
    });

    testWidgets('focus moves to the heading when it appears', (tester) async {
      await needPermission(tester);
      final ctx = FocusManager.instance.primaryFocus?.context;
      expect(ctx, isNotNull);
      expect(
        find.descendant(
          of: find.byWidget(ctx!.widget),
          matching: find.text('Let Kusunga paste for you'),
        ),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('Allow pasting asks macOS; then explains where to turn it on', (
      tester,
    ) async {
      await needPermission(tester);
      port.requestAnswer = false;
      await tester.tap(find.text('Allow pasting'));
      await tester.pump();
      expect(port.calls, contains('requestPostAccess'));
      expect(
        find.text(
          'Turn on Kusunga in System Settings > Privacy & Security > Accessibility.',
        ),
        findsOneWidget,
      );
      expect(find.text('Let Kusunga paste for you'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('the card disappears once pasting is allowed', (tester) async {
      await needPermission(tester);
      port.requestAnswer = true;
      await tester.tap(find.text('Allow pasting'));
      await tester.pump();
      expect(find.text('Let Kusunga paste for you'), findsNothing);
      controller.dispose();
    });

    testWidgets('Not now hides it without asking macOS', (tester) async {
      await needPermission(tester);
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(find.text('Let Kusunga paste for you'), findsNothing);
      expect(port.calls, isNot(contains('requestPostAccess')));
      controller.dispose();
    });

    testWidgets('coming back to the app rechecks the permission', (
      tester,
    ) async {
      await needPermission(tester);
      port.canPostAnswer = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Let Kusunga paste for you'), findsNothing);
      controller.dispose();
    });

    testWidgets('never shown on Windows', (tester) async {
      await show(tester, isMac: false);
      source.copy('x');
      port.press();
      port.pasteAnswer = PasteOutcome.noPermission;
      await controller.pasteItem(history.items.single.id);
      await tester.pump();
      expect(find.text('Let Kusunga paste for you'), findsNothing);
      controller.dispose();
    });
  });

  group('sizes and accessibility', () {
    testWidgets('360 px wide at 200% text, with the card: no overflow', (
      tester,
    ) async {
      port.registerAnswer = (_) => ShortcutRegistration.taken;
      await show(tester, size: const Size(360, 640), textScale: 2);
      source.copy('x');
      port.press();
      port.pasteAnswer = PasteOutcome.noPermission;
      await controller.pasteItem(history.items.single.id);
      await tester.pump();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    for (final b in Brightness.values) {
      testWidgets('contrast and names, ${b.name}', (tester) async {
        final handle = tester.ensureSemantics();
        port.registerAnswer = (_) => ShortcutRegistration.taken;
        await show(tester, brightness: b);
        source.copy('x');
        port.press();
        port.pasteAnswer = PasteOutcome.noPermission;
        await controller.pasteItem(history.items.single.id);
        await tester.pump();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
        controller.dispose();
      });
    }
  });
}
