// Tester probes for the picker shortcut: every invalid form, the round trip
// of every valid one, and shortcuts that would break the paste itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/picker/shortcut.dart';

import 'fake_picker_port.dart';

void main() {
  group('parse: every damaged saved value falls back (returns null)', () {
    const bad = [
      '',
      ' ',
      '+',
      '++',
      'v',
      'meta',
      'meta+',
      '+v',
      'meta++v',
      'META+V',
      'Meta+v',
      'meta+V',
      ' meta+v',
      'meta+v ',
      'meta+v\n',
      'meta +v',
      'meta+v+',
      'meta+v+meta',
      'meta+meta+v',
      'shift+v',
      'shift+shift+v',
      'meta+shift',
      'meta+shift+',
      'cmd+v',
      'command+v',
      'win+v',
      'ctrl+f0',
      'ctrl+f13',
      'ctrl+f01',
      'ctrl+f1 ',
      'ctrl+vv',
      'ctrl+é',
      'ctrl+٣', // Arabic-indic digit three
      'ctrl+ａ', // full-width a
      'ctrl+enter',
      'ctrl+tab',
      'ctrl+escape',
      'ctrl+\u0000',
      'ctrl+v\u0000',
      'ctrl+Space',
      'ctrl+space+space',
    ];
    for (final text in bad) {
      test('"${text.replaceAll('\n', r'\n').replaceAll('\u0000', r'\0')}"', () {
        expect(PickerShortcut.parse(text), isNull);
      });
    }

    test('null, and a 10,000 character value, are null and cheap', () {
      expect(PickerShortcut.parse(null), isNull);
      final sw = Stopwatch()..start();
      expect(PickerShortcut.parse('meta+${'x' * 10000}'), isNull);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  group('round trip', () {
    test('every valid shortcut survives serialize then parse', () {
      var count = 0;
      for (var mask = 1; mask < 16; mask++) {
        final mods = <ShortcutModifier>{
          for (var i = 0; i < 4; i++)
            if (mask & (1 << i) != 0) ShortcutModifier.values[i],
        };
        for (final key in PickerShortcut.allowedKeys) {
          final s = PickerShortcut(mods, key);
          final back = PickerShortcut.parse(s.serialized);
          if (s.isValid) {
            expect(back, s, reason: s.serialized);
            expect(back!.serialized, s.serialized);
            count++;
          } else {
            expect(back, isNull, reason: s.serialized);
          }
        }
      }
      // 49 keys x (15 modifier sets minus the 1 that is shift alone)
      expect(count, 49 * 14);
    });

    test('the key list is exactly a-z, 0-9, F1-F12 and space', () {
      expect(PickerShortcut.allowedKeys.length, 26 + 10 + 12 + 1);
    });

    test('display never throws for any valid shortcut, both platforms', () {
      for (final key in PickerShortcut.allowedKeys) {
        for (final isMac in [true, false]) {
          final text = PickerShortcut({
            ShortcutModifier.ctrl,
            ShortcutModifier.shift,
          }, key).display(isMac: isMac);
          expect(text, isNotEmpty);
        }
      }
    });
  });

  group('a shortcut must not break copy and paste themselves', () {
    // BUG-K1: the picker pastes by sending Cmd+V (Mac) / Ctrl+V (Windows). If
    // the user picks that very combination as the picker shortcut, the
    // synthetic paste key opens the picker again (RegisterHotKey also fires
    // for SendInput), so nothing is ever pasted; and Cmd/Ctrl+C, X, V, A, Z
    // stop working in every app. The setting should refuse them.
    for (final isMac in [true, false]) {
      final os = isMac ? 'Mac' : 'Windows';
      final main = isMac ? ShortcutModifier.meta : ShortcutModifier.ctrl;
      for (final key in ['v', 'c', 'x', 'a', 'z']) {
        test('$os: ${isMac ? 'Cmd' : 'Ctrl'}+$key is refused', () async {
          final port = FakePickerPort();
          final c = PickerController(
            port: port,
            log: const NullErrorLog(),
            isMac: isMac,
          );
          addTearDown(c.dispose);
          await c.start();
          final before = port.registered.length;
          final answer = await c.changeShortcut(PickerShortcut({main}, key));
          expect(answer, isNot(ShortcutChange.saved));
          expect(port.registered.length, before, reason: 'it was registered');
        });
      }
    }
  });
}
