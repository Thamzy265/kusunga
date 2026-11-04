// Tester probes for the picker controller: big and hostile texts, timing
// boundaries, races between the shortcut, Esc, a paste and a closing history,
// and a saved shortcut that comes back after a restart.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/shortcut.dart';

import '../support/fakes.dart';
import 'fake_picker_port.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

final _rlo = String.fromCharCode(0x202E);

void main() {
  late FakePickerPort port;
  late FakeLog log;
  late FakeClipboardSource source;
  late HistoryService history;
  late PickerController c;

  PickerController build({bool isMac = true}) {
    c = PickerController(port: port, log: log, isMac: isMac);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    port = FakePickerPort();
    log = FakeLog();
    source = FakeClipboardSource();
    history = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
    )..start();
    addTearDown(history.dispose);
  });

  int save(String text) {
    source.copy(text);
    return history.items.first.id;
  }

  Future<void> open() async {
    await build().start();
    await c.attach(history);
    port.press();
  }

  group('texts handed to the paste, byte for byte', () {
    test(
      'a 1 MiB item is pasted whole, not as its 2,000 character preview',
      () async {
        final big = 'ab${'x' * (1024 * 1024 - 4)}yz'; // exactly 1 MiB of ASCII
        expect(big.length, 1024 * 1024);
        final id = save(big);
        expect(history.items.single.isTruncated, isTrue);
        await open();
        await c.pasteItem(id);
        expect(port.pastes.single.text.length, big.length);
        expect(port.pastes.single.text == big, isTrue);
      },
    );

    test(
      'NUL, bidi and control characters reach the paste unchanged',
      () async {
        final hostile = 'a\u0000b${_rlo}c\u200Bd\u0007e\u2028f\r\ng\u{1F600}';
        final id = save(hostile);
        await open();
        await c.pasteItem(id);
        // The picker shows them as visible codes; what is pasted is the real
        // text, not the display form.
        expect(port.pastes.single.text, hostile);
      },
    );

    test('leading and trailing white space is kept', () async {
      const spaced = '  \tkeep me  \n';
      final id = save(spaced);
      await open();
      await c.pasteItem(id);
      expect(port.pastes.single.text, spaced);
    });
  });

  group('timing and races', () {
    testWidgets('the toast is there at 3,999 ms and gone at 4,000 ms', (
      tester,
    ) async {
      final id = save('x');
      port.pasteAnswer = PasteOutcome.focusTimeout;
      await open();
      await c.pasteItem(id);
      expect(c.mode, WindowMode.toast);
      await tester.pump(const Duration(milliseconds: 3999));
      expect(c.mode, WindowMode.toast);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(c.mode, WindowMode.manage);
      expect(port.calls.where((x) => x == 'hideToast').length, 1);
    });

    test('Esc while a paste is running does nothing', () async {
      final id = save('x');
      port.pasteGate = Completer<void>();
      await open();
      final paste = c.pasteItem(id);
      await c.closePicker();
      expect(port.calls, isNot(contains('close')));
      port.pasteGate!.complete();
      await paste;
      expect(c.mode, WindowMode.manage);
    });

    test(
      'losing focus while a paste is running does not end it early',
      () async {
        final id = save('x');
        port.pasteGate = Completer<void>();
        port.pasteAnswer = PasteOutcome.focusTimeout;
        await open();
        final paste = c.pasteItem(id);
        port.dismiss();
        expect(c.mode, WindowMode.picker);
        port.pasteGate!.complete();
        await paste;
        expect(c.mode, WindowMode.toast);
        c.dispose();
      },
    );

    test('the history closing during a paste does not throw', () async {
      final id = save('x');
      port.pasteGate = Completer<void>();
      await open();
      final paste = c.pasteItem(id);
      await history.close();
      port.pasteGate!.complete();
      await paste;
      expect(c.mode, WindowMode.manage);
    });

    test(
      'an item deleted just before Enter pastes nothing and shows no toast',
      () async {
        final a = save('keep');
        final b = save('doomed');
        await open();
        history.delete(b);
        await c.pasteItem(b);
        expect(port.pastes, isEmpty);
        expect(c.toast, isNull);
        expect(c.mode, WindowMode.picker);
        await c.pasteItem(a);
        expect(port.pastes.single.text, 'keep');
      },
    );

    test(
      'the same item twice at once pastes once even if native is slow',
      () async {
        final id = save('once');
        port.pasteGate = Completer<void>();
        await open();
        final first = c.pasteItem(id);
        final second = c.pasteItem(id);
        final third = c.pasteItem(id);
        port.pasteGate!.complete();
        await Future.wait([first, second, third]);
        expect(port.pastes.length, 1);
      },
    );

    test('three quick shortcut presses are one picker', () async {
      await open();
      var changes = 0;
      c.addListener(() => changes++);
      port.press();
      port.press();
      expect(c.mode, WindowMode.picker);
      expect(changes, 0);
      expect(port.calls.where((x) => x == 'open'), isEmpty);
    });

    testWidgets(
      'a toast timer from before does not close a picker opened later',
      (tester) async {
        final id = save('x');
        port.pasteAnswer = PasteOutcome.targetGone;
        await open();
        await c.pasteItem(id);
        await tester.pump(const Duration(seconds: 2));
        port.press();
        expect(c.mode, WindowMode.picker);
        await tester.pump(const Duration(seconds: 5));
        expect(c.mode, WindowMode.picker, reason: 'old timer fired');
      },
    );

    testWidgets('two toasts in a row: the second gets its full 4 s', (
      tester,
    ) async {
      final id = save('x');
      port.pasteAnswer = PasteOutcome.targetGone;
      await open();
      await c.pasteItem(id);
      await tester.pump(const Duration(seconds: 3));
      port.press();
      await c.pasteItem(id);
      expect(c.mode, WindowMode.toast);
      await tester.pump(
        const Duration(milliseconds: 1500),
      ); // 4.5 s after the first
      expect(
        c.mode,
        WindowMode.toast,
        reason: 'first timer cut the second toast',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(c.mode, WindowMode.manage);
    });
  });

  group('log never learns about content', () {
    test('every outcome logs codes only', () async {
      const secret = 'hunter2-SECRET-TEXT';
      final id = save(secret);
      for (final outcome in PasteOutcome.values) {
        port.pasteAnswer = outcome;
        await open();
        await c.pasteItem(id);
        c.dispose();
        port = FakePickerPort()..pasteAnswer = outcome;
      }
      expect(log.details.every((d) => d == null), isTrue);
      expect(log.codes.map((e) => e.name).join(), isNot(contains('hunter2')));
    });
  });

  group('the saved shortcut', () {
    for (final bad in ['12', '0', 'meta+v+x', 'shift+v', 'META+V', '\u0000']) {
      test(
        'a damaged saved value "$bad" keeps the default and does not throw',
        () async {
          final store = MemoryHistoryStore()
            ..writeSetting('picker_shortcut', bad.isEmpty ? 'x' : bad);
          final h = HistoryService(store: store, source: source, log: log)
            ..start();
          addTearDown(h.dispose);
          await build().start();
          await c.attach(h);
          expect(c.shortcut.serialized, 'shift+meta+v');
          expect(port.registered.length, 1);
          expect(c.shortcutProblem, isNull);
        },
      );
    }

    test('survives a restart through the real encrypted store', () async {
      final dir = Directory.systemTemp.createTempSync('kusunga_pick_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/kusunga.db';

      var store = SqliteHistoryStore.open(path: path, keyHex: _key);
      var h = HistoryService(store: store, source: source, log: log)..start();
      await build().start();
      await c.attach(h);
      expect(
        await c.changeShortcut(
          PickerShortcut({ShortcutModifier.ctrl, ShortcutModifier.alt}, 'k'),
        ),
        ShortcutChange.saved,
      );
      await h.close();
      c.dispose();

      port = FakePickerPort();
      store = SqliteHistoryStore.open(path: path, keyHex: _key);
      h = HistoryService(store: store, source: FakeClipboardSource(), log: log)
        ..start();
      addTearDown(h.close);
      await build().start();
      await c.attach(h);
      expect(c.shortcut.serialized, 'ctrl+alt+k');
      expect(port.registered.last.serialized, 'ctrl+alt+k');
    });

    test(
      'taken at start-up, then re-entered after the other app let go: saved, banner gone',
      () async {
        var taken = true;
        port.registerAnswer = (_) => taken
            ? ShortcutRegistration.taken
            : ShortcutRegistration.registered;
        await build().start();
        expect(c.shortcutProblem, ShortcutProblem.taken);
        taken = false;
        expect(await c.changeShortcut(c.shortcut), ShortcutChange.saved);
        expect(c.shortcutProblem, isNull);
      },
    );

    test(
      'recording started twice and cancelled puts the shortcut back once',
      () async {
        await build().start();
        await c.beginRecording();
        await c.beginRecording();
        await c.endRecording();
        await c.endRecording();
        expect(port.calls.where((x) => x == 'unregister').length, 1);
        expect(port.calls.where((x) => x.startsWith('register')).length, 2);
      },
    );
  });
}
