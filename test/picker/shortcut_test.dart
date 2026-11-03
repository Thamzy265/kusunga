import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/picker/shortcut.dart';

void main() {
  group('defaults', () {
    test('Mac default is Cmd+Shift+V', () {
      final s = PickerShortcut.defaultFor(isMac: true);
      expect(s.serialized, 'shift+meta+v');
      expect(s.display(isMac: true), '⇧⌘V');
      expect(s.isValid, isTrue);
    });

    test('Windows default is Ctrl+Shift+V', () {
      final s = PickerShortcut.defaultFor(isMac: false);
      expect(s.serialized, 'ctrl+shift+v');
      expect(s.display(isMac: false), 'Ctrl+Shift+V');
      expect(s.isValid, isTrue);
    });
  });

  group('parse and serialise', () {
    test('round trip keeps the canonical order whatever order it came in', () {
      final s = PickerShortcut.parse('meta+alt+shift+ctrl+k')!;
      expect(s.serialized, 'ctrl+alt+shift+meta+k');
      expect(PickerShortcut.parse(s.serialized), s);
    });

    test('accepts letters, digits, F keys and space', () {
      for (final key in ['a', 'z', '0', '9', 'f1', 'f12', 'space']) {
        expect(PickerShortcut.parse('ctrl+$key')?.key, key, reason: key);
      }
    });

    test('rejects anything that is not a valid combination', () {
      for (final bad in [
        null,
        '',
        'v',
        'shift+v', // shift alone is not enough
        'ctrl+shift', // no key
        'ctrl+a+b', // two keys
        'ctrl+f13',
        'ctrl+enter',
        'ctrl+ctrl+v', // repeated modifier
        'CTRL+V ',
        'ctrl+V',
        'ctrl+é',
        'ctrl+${'a' * 200}',
        'ctrl+;',
      ]) {
        expect(PickerShortcut.parse(bad), isNull, reason: '$bad');
      }
    });

    test('a combination with only Shift is not valid', () {
      expect(
        const PickerShortcut({ShortcutModifier.shift}, 'v').isValid,
        false,
      );
      expect(const PickerShortcut({}, 'v').isValid, false);
    });

    test('any one of Cmd, Ctrl or Alt is enough', () {
      for (final m in [
        ShortcutModifier.ctrl,
        ShortcutModifier.alt,
        ShortcutModifier.meta,
      ]) {
        expect(PickerShortcut({m}, 'v').isValid, isTrue);
      }
    });
  });

  group('display', () {
    test('Mac shows symbols in the system order', () {
      final s = PickerShortcut.parse('ctrl+alt+shift+meta+f5')!;
      expect(s.display(isMac: true), '⌃⌥⇧⌘F5');
    });

    test('Windows shows names, with Win for the Windows key', () {
      final s = PickerShortcut.parse('ctrl+alt+meta+space')!;
      expect(s.display(isMac: false), 'Ctrl+Alt+Win+Space');
    });
  });

  group('help text for an unusable combination', () {
    test('names the keys of the platform', () {
      expect(
        PickerShortcut.needModifierMessage(isMac: true),
        'Use at least one of ⌘, ⌃ or ⌥ with a key.',
      );
      expect(
        PickerShortcut.needModifierMessage(isMac: false),
        'Use at least one of Ctrl, Alt or Win with a key.',
      );
    });
  });

  group('recording a key press', () {
    test('Mac uses the physical key, so the trigger is the key pressed', () {
      final s = PickerShortcut.fromKey(
        physical: PhysicalKeyboardKey.keyV,
        logical: LogicalKeyboardKey.keyZ, // a different layout label
        modifiers: {ShortcutModifier.meta, ShortcutModifier.shift},
        isMac: true,
      );
      expect(s?.serialized, 'shift+meta+v');
    });

    test('Windows uses the logical key, as RegisterHotKey does', () {
      final s = PickerShortcut.fromKey(
        physical: PhysicalKeyboardKey.keyY,
        logical: LogicalKeyboardKey.keyZ,
        modifiers: {ShortcutModifier.ctrl},
        isMac: false,
      );
      expect(s?.serialized, 'ctrl+z');
    });

    test('digits, F keys and space are recognised', () {
      PickerShortcut? rec(PhysicalKeyboardKey p, LogicalKeyboardKey l) =>
          PickerShortcut.fromKey(
            physical: p,
            logical: l,
            modifiers: {ShortcutModifier.alt},
            isMac: true,
          );
      expect(
        rec(PhysicalKeyboardKey.digit7, LogicalKeyboardKey.digit7)?.key,
        '7',
      );
      expect(rec(PhysicalKeyboardKey.f9, LogicalKeyboardKey.f9)?.key, 'f9');
      expect(
        rec(PhysicalKeyboardKey.space, LogicalKeyboardKey.space)?.key,
        'space',
      );
    });

    test(
      'a modifier key on its own, or an unsupported key, records nothing',
      () {
        expect(
          PickerShortcut.fromKey(
            physical: PhysicalKeyboardKey.metaLeft,
            logical: LogicalKeyboardKey.metaLeft,
            modifiers: {ShortcutModifier.meta},
            isMac: true,
          ),
          isNull,
        );
        expect(
          PickerShortcut.fromKey(
            physical: PhysicalKeyboardKey.enter,
            logical: LogicalKeyboardKey.enter,
            modifiers: {ShortcutModifier.meta},
            isMac: true,
          ),
          isNull,
        );
      },
    );

    test('a key with no modifier is returned so the caller can explain', () {
      final s = PickerShortcut.fromKey(
        physical: PhysicalKeyboardKey.keyV,
        logical: LogicalKeyboardKey.keyV,
        modifiers: {},
        isMac: true,
      );
      expect(s?.isValid, isFalse);
      expect(s?.key, 'v');
    });
  });
}
