import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/shortcut.dart';

import '../support/fakes.dart';
import 'fake_picker_port.dart';

void main() {
  late FakePickerPort port;
  late FakeLog log;
  late FakeClipboardSource source;
  late MemoryHistoryStore store;
  late HistoryService history;
  late PickerController c;
  PickerController? built;

  /// A widget test that disposes the controller before the test ends: a toast
  /// timer still pending is a test failure otherwise.
  void ctest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      built = null;
      await body(tester);
      built?.dispose();
    });
  }

  PickerController build({bool isMac = true}) {
    c = PickerController(
      port: port,
      log: log,
      isMac: isMac,
      toastDuration: const Duration(seconds: 4),
    );
    built = c;
    return c;
  }

  setUp(() {
    port = FakePickerPort();
    log = FakeLog();
    source = FakeClipboardSource();
    store = MemoryHistoryStore();
    history = HistoryService(store: store, source: source, log: log)..start();
    addTearDown(history.dispose);
  });

  int saveText(String text) {
    source.copy(text);
    return history.items.first.id;
  }

  group('start', () {
    ctest('registers the platform default shortcut', (tester) async {
      await build().start();
      expect(port.registered.single.serialized, 'shift+meta+v');
      expect(c.shortcut.display(isMac: true), '⇧⌘V');
      expect(c.shortcutProblem, isNull);
      expect(c.mode, WindowMode.manage);
    });

    ctest('Windows default is Ctrl+Shift+V', (tester) async {
      await build(isMac: false).start();
      expect(port.registered.single.serialized, 'ctrl+shift+v');
    });

    ctest('a taken shortcut is reported: banner text and log code', (
      tester,
    ) async {
      port.registerAnswer = (_) => ShortcutRegistration.taken;
      await build().start();
      expect(c.shortcutProblem, ShortcutProblem.taken);
      expect(
        c.shortcutBannerText,
        "Kusunga's shortcut ⇧⌘V is used by another app. Choose another.",
      );
      expect(log.codes, [LogCode.hotkeyRegisterFailed]);
    });

    ctest('any other registration failure is reported the same way', (
      tester,
    ) async {
      port.registerAnswer = (_) => ShortcutRegistration.failed;
      await build(isMac: false).start();
      expect(c.shortcutProblem, ShortcutProblem.taken);
      expect(
        c.shortcutBannerText,
        "Kusunga's shortcut Ctrl+Shift+V is used by another app. Choose another.",
      );
      expect(log.codes, [LogCode.hotkeyRegisterFailed]);
    });

    ctest('start twice registers once', (tester) async {
      await build().start();
      await c.start();
      expect(port.registered.length, 1);
    });
  });

  group('opening and closing the picker', () {
    ctest('the shortcut switches to picker mode', (tester) async {
      await build().start();
      var notified = 0;
      c.addListener(() => notified++);
      port.press();
      expect(c.mode, WindowMode.picker);
      expect(notified, 1);
    });

    ctest('pressing it again while open changes nothing', (tester) async {
      await build().start();
      port.press();
      var notified = 0;
      c.addListener(() => notified++);
      port.press();
      expect(c.mode, WindowMode.picker);
      expect(notified, 0);
    });

    ctest('the tray item asks native to open the picker', (tester) async {
      await build().start();
      c.openFromTray();
      expect(port.calls, contains('open'));
    });

    ctest('Esc asks native to close, then goes back to manage mode', (
      tester,
    ) async {
      await build().start();
      port.press();
      await c.closePicker();
      expect(port.calls.last, 'close');
      expect(c.mode, WindowMode.manage);
    });

    ctest('closing when it is not open does nothing', (tester) async {
      await build().start();
      await c.closePicker();
      expect(port.calls, isNot(contains('close')));
    });

    ctest('losing focus (click outside) goes back to manage mode', (
      tester,
    ) async {
      await build().start();
      port.press();
      port.dismiss();
      expect(c.mode, WindowMode.manage);
      expect(port.calls, isNot(contains('close')));
    });

    ctest('a late dismissal while not open is ignored', (tester) async {
      await build().start();
      port.dismiss();
      expect(c.mode, WindowMode.manage);
    });

    ctest('after dispose, events change nothing', (tester) async {
      await build().start();
      c.dispose();
      port.press();
      expect(c.mode, WindowMode.manage);
    });
  });

  group('pasting', () {
    Future<void> attachAndOpen() async {
      await build().start();
      await c.attach(history);
      port.press();
    }

    ctest('sends the whole text and posts the keystroke', (tester) async {
      final long = 'z' * 5000;
      final id = saveText(long);
      await attachAndOpen();
      await c.pasteItem(id);
      expect(port.pastes.single.text, long);
      expect(port.pastes.single.post, isTrue);
      expect(c.mode, WindowMode.manage);
      expect(c.toast, isNull);
      expect(log.codes, isEmpty);
    });

    ctest('copy-only mode never asks for the keystroke', (tester) async {
      final id = saveText('a');
      history.saveSetting('paste_mode', 'copy_only');
      await attachAndOpen();
      expect(c.pasteMode, PasteMode.copyOnly);
      port.pasteAnswer = PasteOutcome.copyOnly;
      await c.pasteItem(id);
      expect(port.pastes.single.post, isFalse);
      expect(c.toast, ToastKind.copied);
    });

    ctest('Mac without permission: toast, card, log code', (tester) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.noPermission;
      await c.pasteItem(id);
      expect(c.mode, WindowMode.toast);
      expect(c.toast, ToastKind.copiedNoPermission);
      expect(
        c.toastText,
        'Copied — press ⌘V to paste. Allow pasting in Kusunga to do this for you.',
      );
      expect(c.permissionCardVisible, isTrue);
      expect(log.codes, [LogCode.pastePermissionMissing]);
      expect(port.calls.last, 'showToast');
    });

    ctest('focus not back in time: copy-only toast and log code', (
      tester,
    ) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await c.pasteItem(id);
      expect(c.toastText, 'Copied — press ⌘V to paste.');
      expect(c.permissionCardVisible, isFalse);
      expect(log.codes, [LogCode.pasteFocusTimeout]);
    });

    ctest('the app that had focus is gone: same toast, own log code', (
      tester,
    ) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.targetGone;
      await c.pasteItem(id);
      expect(c.toastText, 'Copied — press ⌘V to paste.');
      expect(log.codes, [LogCode.pasteTargetGone]);
    });

    ctest('Windows administrator window: its own toast text', (tester) async {
      final id = saveText('a');
      await build(isMac: false).start();
      await c.attach(history);
      port.press();
      port.pasteAnswer = PasteOutcome.targetElevated;
      await c.pasteItem(id);
      expect(
        c.toastText,
        "Copied — press Ctrl+V to paste. Kusunga can't paste into apps run as administrator.",
      );
      expect(c.permissionCardVisible, isFalse);
      expect(log.codes, [LogCode.pasteTargetElevated]);
    });

    ctest('Windows other copy-only outcomes say Ctrl+V', (tester) async {
      final id = saveText('a');
      await build(isMac: false).start();
      await c.attach(history);
      port.press();
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await c.pasteItem(id);
      expect(c.toastText, 'Copied — press Ctrl+V to paste.');
    });

    ctest('a clipboard that could not be written says so', (tester) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.failed;
      await c.pasteItem(id);
      expect(c.toastText, "Couldn't copy. Try again.");
    });

    ctest('a port that throws is treated as a failed copy', (tester) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteThrows = StateError('boom');
      await c.pasteItem(id);
      expect(c.toast, ToastKind.copyFailed);
      expect(c.mode, WindowMode.toast);
    });

    ctest('the toast hides itself after 4 seconds', (tester) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await c.pasteItem(id);
      await tester.pump(const Duration(seconds: 3));
      expect(c.mode, WindowMode.toast);
      await tester.pump(const Duration(seconds: 2));
      expect(c.mode, WindowMode.manage);
      expect(c.toast, isNull);
      expect(port.calls.last, 'hideToast');
    });

    ctest('the shortcut while a toast shows opens the picker at once', (
      tester,
    ) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await c.pasteItem(id);
      port.press();
      expect(c.mode, WindowMode.picker);
      expect(c.toast, isNull);
      await tester.pump(const Duration(seconds: 10));
      expect(c.mode, WindowMode.picker, reason: 'the old timer must not fire');
      expect(port.calls, isNot(contains('hideToast')));
    });

    ctest('Enter twice pastes once', (tester) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteGate = Completer<void>();
      final first = c.pasteItem(id);
      final second = c.pasteItem(id);
      port.pasteGate!.complete();
      await Future.wait([first, second]);
      expect(port.pastes.length, 1);
    });

    ctest('the shortcut during a paste is ignored', (tester) async {
      final id = saveText('a');
      await attachAndOpen();
      port.pasteGate = Completer<void>();
      final done = c.pasteItem(id);
      port.press();
      port.pasteGate!.complete();
      await done;
      expect(c.mode, WindowMode.manage);
    });

    ctest('an item that is gone pastes nothing and keeps the picker', (
      tester,
    ) async {
      await attachAndOpen();
      await c.pasteItem(424242);
      expect(port.pastes, isEmpty);
      expect(c.mode, WindowMode.picker);
    });

    ctest('while the history is still opening nothing is pasted', (
      tester,
    ) async {
      await build().start();
      port.press();
      await c.pasteItem(1);
      expect(port.pastes, isEmpty);
      expect(c.mode, WindowMode.picker);
    });

    ctest('pasting when the picker is not open does nothing', (tester) async {
      final id = saveText('a');
      await build().start();
      await c.attach(history);
      await c.pasteItem(id);
      expect(port.pastes, isEmpty);
    });

    ctest('the log never gets text, only codes', (tester) async {
      final id = saveText('top secret words');
      await attachAndOpen();
      port.pasteAnswer = PasteOutcome.targetGone;
      await c.pasteItem(id);
      expect(log.codes.map((e) => e.name).join(), isNot(contains('secret')));
      expect(log.details, [null]);
    });
  });

  group('settings from the history', () {
    ctest('a saved shortcut is registered once the history opens', (
      tester,
    ) async {
      history.saveSetting('picker_shortcut', 'ctrl+alt+k');
      await build().start();
      await c.attach(history);
      expect(port.registered.last.serialized, 'ctrl+alt+k');
      expect(c.shortcut.serialized, 'ctrl+alt+k');
      expect(c.shortcutProblem, isNull);
    });

    ctest('a saved shortcut equal to the default registers nothing more', (
      tester,
    ) async {
      history.saveSetting('picker_shortcut', 'shift+meta+v');
      await build().start();
      await c.attach(history);
      expect(port.registered.length, 1);
    });

    ctest('a damaged saved shortcut is ignored: the default stays', (
      tester,
    ) async {
      history.saveSetting('picker_shortcut', 'banana');
      await build().start();
      await c.attach(history);
      expect(c.shortcut.serialized, 'shift+meta+v');
      expect(c.shortcutProblem, isNull);
    });

    ctest('a saved shortcut that is taken keeps the default working', (
      tester,
    ) async {
      history.saveSetting('picker_shortcut', 'ctrl+alt+k');
      await build().start();
      port.registerAnswer = (s) => s.serialized == 'ctrl+alt+k'
          ? ShortcutRegistration.taken
          : ShortcutRegistration.registered;
      await c.attach(history);
      expect(c.shortcutProblem, ShortcutProblem.taken);
      expect(
        c.shortcutBannerText,
        "Kusunga's shortcut ⌃⌥K is used by another app. Choose another.",
      );
      expect(log.codes, [LogCode.hotkeyRegisterFailed]);
    });

    ctest('an unknown paste mode means auto', (tester) async {
      history.saveSetting('paste_mode', 'weird');
      await build().start();
      await c.attach(history);
      expect(c.pasteMode, PasteMode.auto);
    });

    ctest('a shortcut chosen before the history opened is saved then', (
      tester,
    ) async {
      await build().start();
      expect(
        await c.changeShortcut(PickerShortcut.parse('alt+j')!),
        ShortcutChange.saved,
      );
      await c.attach(history);
      expect(history.setting('picker_shortcut'), 'alt+j');
      expect(c.shortcut.serialized, 'alt+j');
    });

    ctest('the picker opens from memory while the history is opening', (
      tester,
    ) async {
      await build().start();
      port.press();
      expect(c.mode, WindowMode.picker);
      expect(c.history, isNull);
    });
  });

  group('changing the shortcut', () {
    ctest('a free combination is registered and saved', (tester) async {
      await build().start();
      await c.attach(history);
      final r = await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(r, ShortcutChange.saved);
      expect(c.shortcut.serialized, 'ctrl+alt+k');
      expect(history.setting('picker_shortcut'), 'ctrl+alt+k');
      expect(c.shortcutProblem, isNull);
    });

    ctest('a taken combination is refused and the old one is kept', (
      tester,
    ) async {
      await build().start();
      await c.attach(history);
      port.registerAnswer = (_) => ShortcutRegistration.taken;
      final r = await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(r, ShortcutChange.taken);
      expect(c.shortcut.serialized, 'shift+meta+v');
      expect(history.setting('picker_shortcut'), isNull);
      expect(log.codes, [LogCode.hotkeyRegisterFailed]);
    });

    ctest('no Cmd, Ctrl or Alt: refused without asking native', (tester) async {
      await build().start();
      final before = port.calls.length;
      final r = await c.changeShortcut(
        const PickerShortcut({ShortcutModifier.shift}, 'v'),
      );
      expect(r, ShortcutChange.needModifier);
      expect(port.calls.length, before);
    });

    ctest('the same shortcut again is a quiet success', (tester) async {
      await build().start();
      final before = port.calls.length;
      final r = await c.changeShortcut(PickerShortcut.defaultFor(isMac: true));
      expect(r, ShortcutChange.saved);
      expect(port.calls.length, before);
    });

    ctest('a good change clears the start-up banner', (tester) async {
      port.registerAnswer = (_) => ShortcutRegistration.taken;
      await build().start();
      expect(c.shortcutProblem, isNotNull);
      port.registerAnswer = (_) => ShortcutRegistration.registered;
      await c.attach(history);
      await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(c.shortcutProblem, isNull);
      expect(c.shortcutBannerText, isNull);
    });

    ctest('registered but not saved is reported as such', (tester) async {
      final flaky = FlakyStore(MemoryHistoryStore());
      final h = HistoryService(store: flaky, source: source, log: log)..start();
      addTearDown(h.dispose);
      await build().start();
      await c.attach(h);
      flaky.failWrites = true;
      final r = await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(r, ShortcutChange.notSaved);
      expect(
        c.shortcut.serialized,
        'ctrl+alt+k',
        reason: 'it works until quit',
      );
    });
  });

  group('opening the main window from the tray', () {
    ctest('while the picker is open it is closed first', (tester) async {
      await build().start();
      port.press();
      await c.prepareManageWindow();
      expect(port.calls.last, 'close');
      expect(c.mode, WindowMode.manage);
    });

    ctest('while a toast shows it is hidden at once and its timer stops', (
      tester,
    ) async {
      final id = saveText('a');
      await build().start();
      await c.attach(history);
      port.press();
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await c.pasteItem(id);
      await c.prepareManageWindow();
      expect(port.calls.last, 'hideToast');
      expect(c.mode, WindowMode.manage);
      expect(c.toast, isNull);
      await tester.pump(const Duration(seconds: 10));
      expect(port.calls.where((e) => e == 'hideToast').length, 1);
    });

    ctest('in manage mode nothing happens', (tester) async {
      await build().start();
      final before = port.calls.length;
      await c.prepareManageWindow();
      expect(port.calls.length, before);
    });
  });

  group('recording a new shortcut', () {
    ctest('the current shortcut is released while keys are recorded', (
      tester,
    ) async {
      await build().start();
      await c.beginRecording();
      expect(port.calls.last, 'unregister');
      await c.beginRecording();
      expect(port.calls.where((e) => e == 'unregister').length, 1);
    });

    ctest('cancelling puts the same shortcut back', (tester) async {
      await build().start();
      await c.beginRecording();
      await c.endRecording();
      expect(port.calls.last, 'register shift+meta+v');
      await c.endRecording();
      expect(
        port.calls.where((e) => e == 'register shift+meta+v').length,
        2,
        reason: 'only once more',
      );
    });

    ctest('cancelling without recording does nothing', (tester) async {
      await build().start();
      final before = port.calls.length;
      await c.endRecording();
      expect(port.calls.length, before);
    });

    ctest('a taken choice puts the old shortcut back', (tester) async {
      await build().start();
      await c.attach(history);
      await c.beginRecording();
      port.registerAnswer = (s) => s.serialized == 'ctrl+alt+k'
          ? ShortcutRegistration.taken
          : ShortcutRegistration.registered;
      final r = await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(r, ShortcutChange.taken);
      expect(port.calls.last, 'register shift+meta+v');
      expect(c.shortcut.serialized, 'shift+meta+v');
    });

    ctest('recording the very same shortcut puts it back too', (tester) async {
      await build().start();
      await c.beginRecording();
      final r = await c.changeShortcut(PickerShortcut.defaultFor(isMac: true));
      expect(r, ShortcutChange.saved);
      expect(port.calls.last, 'register shift+meta+v');
    });

    ctest('a good choice replaces it, with nothing put back', (tester) async {
      await build().start();
      await c.attach(history);
      await c.beginRecording();
      await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(port.calls.last, 'register ctrl+alt+k');
      await c.endRecording();
      expect(port.calls.last, 'register ctrl+alt+k');
      expect(port.calls.where((e) => e.startsWith('register')).length, 2);
    });

    ctest('a combination with no Cmd, Ctrl or Alt keeps recording', (
      tester,
    ) async {
      await build().start();
      await c.beginRecording();
      await c.changeShortcut(
        const PickerShortcut({ShortcutModifier.shift}, 'v'),
      );
      expect(port.calls.last, 'unregister', reason: 'still released');
      await c.endRecording();
      expect(port.calls.last, 'register shift+meta+v');
    });
  });

  group('memory-only history (C1)', () {
    HistoryService memoryOnly() => HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      notices: {HistoryNotice.memoryOnly},
    )..start();

    ctest('a shortcut that cannot be kept after a quit is not "saved"', (
      tester,
    ) async {
      final h = memoryOnly();
      addTearDown(h.dispose);
      await build().start();
      await c.attach(h);
      final r = await c.changeShortcut(PickerShortcut.parse('ctrl+alt+k')!);
      expect(r, ShortcutChange.notSaved);
      expect(c.shortcut.serialized, 'ctrl+alt+k', reason: 'works this session');
    });

    ctest('a shortcut chosen before the history opened and then not kept '
        'is reported', (tester) async {
      await build().start();
      await c.changeShortcut(PickerShortcut.parse('alt+j')!);
      expect(c.shortcutSaveFailed, isFalse);
      final h = memoryOnly();
      addTearDown(h.dispose);
      await c.attach(h);
      expect(c.shortcutSaveFailed, isTrue);
      expect(c.shortcut.serialized, 'alt+j');
    });

    ctest('a normal history keeps it and reports nothing', (tester) async {
      await build().start();
      await c.changeShortcut(PickerShortcut.parse('alt+j')!);
      await c.attach(history);
      expect(c.shortcutSaveFailed, isFalse);
      expect(history.setting('picker_shortcut'), 'alt+j');
    });
  });

  group('the "Allow pasting" card (Mac)', () {
    Future<void> needPermission() async {
      final id = saveText('a');
      await build().start();
      await c.attach(history);
      port.press();
      port.pasteAnswer = PasteOutcome.noPermission;
      await c.pasteItem(id);
    }

    ctest('asks macOS only when the button is pressed', (tester) async {
      await needPermission();
      expect(port.calls, isNot(contains('requestPostAccess')));
      port.requestAnswer = true;
      await c.allowPasting();
      expect(port.calls, contains('requestPostAccess'));
      expect(c.permissionCardVisible, isFalse);
      expect(history.setting('paste_mode'), 'auto');
    });

    ctest('not allowed yet: explains where to turn it on', (tester) async {
      await needPermission();
      port.requestAnswer = false;
      await c.allowPasting();
      expect(c.permissionCardVisible, isTrue);
      expect(c.permissionHelpVisible, isTrue);
    });

    ctest('"Not now" hides the card until the next paste needs it', (
      tester,
    ) async {
      await needPermission();
      c.dismissPermissionCard();
      expect(c.permissionCardVisible, isFalse);
      expect(port.calls, isNot(contains('requestPostAccess')));
    });

    ctest('the card goes away when permission appears later', (tester) async {
      await needPermission();
      port.canPostAnswer = true;
      await c.recheckPostAccess();
      expect(c.permissionCardVisible, isFalse);
    });

    ctest('rechecking without a card does not ask the system', (tester) async {
      await build().start();
      await c.recheckPostAccess();
      expect(port.calls, isNot(contains('canPost')));
    });

    ctest('no card is ever shown on Windows', (tester) async {
      await build(isMac: false).start();
      port.press();
      await c.attach(history);
      final id = saveText('a');
      port.pasteAnswer = PasteOutcome.noPermission;
      await c.pasteItem(id);
      expect(c.permissionCardVisible, isFalse);
    });
  });

  ctest('dispose cancels the toast timer and stops listening', (tester) async {
    final id = saveText('a');
    await build().start();
    await c.attach(history);
    port.press();
    port.pasteAnswer = PasteOutcome.focusTimeout;
    await c.pasteItem(id);
    c.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(port.calls, isNot(contains('hideToast')));
  });
}
