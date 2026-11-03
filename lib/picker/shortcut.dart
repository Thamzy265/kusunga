import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A modifier key of the picker shortcut. [meta] is Cmd on a Mac and the
/// Windows key on Windows.
enum ShortcutModifier { ctrl, alt, shift, meta }

/// The global shortcut that opens the picker: some modifiers and one key.
///
/// It is saved as text (`shift+meta+v`): modifiers in the fixed order ctrl,
/// alt, shift, meta, then the key. The key is a letter, a digit, `f1` to
/// `f12` or `space`. Native code turns the same names into key codes, so the
/// text is the contract with the Mac and Windows code (see `picker_port.dart`).
@immutable
class PickerShortcut {
  const PickerShortcut(this.modifiers, this.key);

  final Set<ShortcutModifier> modifiers;
  final String key;

  static const _order = [
    ShortcutModifier.ctrl,
    ShortcutModifier.alt,
    ShortcutModifier.shift,
    ShortcutModifier.meta,
  ];

  /// The keys a shortcut may use: letters, digits, F1 to F12 and space.
  static final Set<String> allowedKeys = {
    for (var c = 0x61; c <= 0x7A; c++) String.fromCharCode(c),
    for (var d = 0; d <= 9; d++) '$d',
    for (var f = 1; f <= 12; f++) 'f$f',
    'space',
  };

  /// Cmd+Shift+V on a Mac, Ctrl+Shift+V on Windows (PM decision, 2026-11-04).
  static PickerShortcut defaultFor({required bool isMac}) => PickerShortcut(
    isMac
        ? {ShortcutModifier.shift, ShortcutModifier.meta}
        : {ShortcutModifier.ctrl, ShortcutModifier.shift},
    'v',
  );

  /// At least one of Cmd, Ctrl or Alt (Shift alone would fire while typing),
  /// and a key we can register.
  bool get isValid =>
      allowedKeys.contains(key) &&
      (modifiers.contains(ShortcutModifier.ctrl) ||
          modifiers.contains(ShortcutModifier.alt) ||
          modifiers.contains(ShortcutModifier.meta));

  /// The combinations the editing keys use: Cmd (Ctrl on Windows) alone with
  /// V, C, X, A or Z. As the picker shortcut they would stop copy and paste in
  /// every app, and the paste keystroke Kusunga sends would open the picker
  /// again. With another modifier added (the default Cmd+Shift+V) they are fine.
  bool isReserved({required bool isMac}) {
    final main = isMac ? ShortcutModifier.meta : ShortcutModifier.ctrl;
    return modifiers.length == 1 &&
        modifiers.contains(main) &&
        const {'v', 'c', 'x', 'a', 'z'}.contains(key);
  }

  /// Shown for a [isReserved] combination.
  static const reservedMessage =
      'That shortcut is needed for copy and paste. Choose another.';

  /// The saved form, for example `shift+meta+v`.
  String get serialized => [
    for (final m in _order)
      if (modifiers.contains(m)) m.name,
    key,
  ].join('+');

  /// Reads the saved form. Returns null for anything that is not a valid
  /// shortcut, so a damaged setting falls back to the default.
  static PickerShortcut? parse(String? text) {
    if (text == null || text.length > 64) return null;
    final parts = text.split('+');
    if (parts.length < 2) return null;
    final key = parts.last;
    final mods = <ShortcutModifier>{};
    for (final p in parts.sublist(0, parts.length - 1)) {
      final m = _order.where((m) => m.name == p).firstOrNull;
      if (m == null || !mods.add(m)) return null;
    }
    final shortcut = PickerShortcut(mods, key);
    return shortcut.isValid ? shortcut : null;
  }

  /// How the shortcut is shown: "⇧⌘V" on a Mac, "Ctrl+Shift+V" on Windows.
  String display({required bool isMac}) {
    final keyText = key == 'space' ? 'Space' : key.toUpperCase();
    if (isMac) {
      const glyph = {
        ShortcutModifier.ctrl: '⌃',
        ShortcutModifier.alt: '⌥',
        ShortcutModifier.shift: '⇧',
        ShortcutModifier.meta: '⌘',
      };
      return '${[for (final m in _order)
        if (modifiers.contains(m)) glyph[m]].join()}$keyText';
    }
    const names = {
      ShortcutModifier.ctrl: 'Ctrl',
      ShortcutModifier.alt: 'Alt',
      ShortcutModifier.shift: 'Shift',
      ShortcutModifier.meta: 'Win',
    };
    return [
      for (final m in _order)
        if (modifiers.contains(m)) names[m]!,
      keyText,
    ].join('+');
  }

  /// Shown when the user presses a combination with no Cmd, Ctrl or Alt.
  static String needModifierMessage({required bool isMac}) => isMac
      ? 'Use at least one of ⌘, ⌃ or ⌥ with a key.'
      : 'Use at least one of Ctrl, Alt or Win with a key.';

  /// Turns a key press into a shortcut, or null if the key cannot be used
  /// (a modifier alone, Enter, arrows and so on). The result may still be
  /// invalid (no Cmd, Ctrl or Alt): the caller explains that.
  ///
  /// On a Mac the physical key is used, because the Mac registers a key
  /// position; on Windows the logical key, because Windows registers the key
  /// that makes the letter on the user's layout.
  static PickerShortcut? fromKey({
    required PhysicalKeyboardKey physical,
    required LogicalKeyboardKey logical,
    required Set<ShortcutModifier> modifiers,
    required bool isMac,
  }) {
    final key = isMac ? _physicalNames[physical] : _logicalNames[logical];
    return key == null ? null : PickerShortcut(Set.of(modifiers), key);
  }

  static final Map<PhysicalKeyboardKey, String> _physicalNames = {
    PhysicalKeyboardKey.keyA: 'a',
    PhysicalKeyboardKey.keyB: 'b',
    PhysicalKeyboardKey.keyC: 'c',
    PhysicalKeyboardKey.keyD: 'd',
    PhysicalKeyboardKey.keyE: 'e',
    PhysicalKeyboardKey.keyF: 'f',
    PhysicalKeyboardKey.keyG: 'g',
    PhysicalKeyboardKey.keyH: 'h',
    PhysicalKeyboardKey.keyI: 'i',
    PhysicalKeyboardKey.keyJ: 'j',
    PhysicalKeyboardKey.keyK: 'k',
    PhysicalKeyboardKey.keyL: 'l',
    PhysicalKeyboardKey.keyM: 'm',
    PhysicalKeyboardKey.keyN: 'n',
    PhysicalKeyboardKey.keyO: 'o',
    PhysicalKeyboardKey.keyP: 'p',
    PhysicalKeyboardKey.keyQ: 'q',
    PhysicalKeyboardKey.keyR: 'r',
    PhysicalKeyboardKey.keyS: 's',
    PhysicalKeyboardKey.keyT: 't',
    PhysicalKeyboardKey.keyU: 'u',
    PhysicalKeyboardKey.keyV: 'v',
    PhysicalKeyboardKey.keyW: 'w',
    PhysicalKeyboardKey.keyX: 'x',
    PhysicalKeyboardKey.keyY: 'y',
    PhysicalKeyboardKey.keyZ: 'z',
    PhysicalKeyboardKey.digit0: '0',
    PhysicalKeyboardKey.digit1: '1',
    PhysicalKeyboardKey.digit2: '2',
    PhysicalKeyboardKey.digit3: '3',
    PhysicalKeyboardKey.digit4: '4',
    PhysicalKeyboardKey.digit5: '5',
    PhysicalKeyboardKey.digit6: '6',
    PhysicalKeyboardKey.digit7: '7',
    PhysicalKeyboardKey.digit8: '8',
    PhysicalKeyboardKey.digit9: '9',
    PhysicalKeyboardKey.f1: 'f1',
    PhysicalKeyboardKey.f2: 'f2',
    PhysicalKeyboardKey.f3: 'f3',
    PhysicalKeyboardKey.f4: 'f4',
    PhysicalKeyboardKey.f5: 'f5',
    PhysicalKeyboardKey.f6: 'f6',
    PhysicalKeyboardKey.f7: 'f7',
    PhysicalKeyboardKey.f8: 'f8',
    PhysicalKeyboardKey.f9: 'f9',
    PhysicalKeyboardKey.f10: 'f10',
    PhysicalKeyboardKey.f11: 'f11',
    PhysicalKeyboardKey.f12: 'f12',
    PhysicalKeyboardKey.space: 'space',
  };

  static final Map<LogicalKeyboardKey, String> _logicalNames = {
    LogicalKeyboardKey.keyA: 'a',
    LogicalKeyboardKey.keyB: 'b',
    LogicalKeyboardKey.keyC: 'c',
    LogicalKeyboardKey.keyD: 'd',
    LogicalKeyboardKey.keyE: 'e',
    LogicalKeyboardKey.keyF: 'f',
    LogicalKeyboardKey.keyG: 'g',
    LogicalKeyboardKey.keyH: 'h',
    LogicalKeyboardKey.keyI: 'i',
    LogicalKeyboardKey.keyJ: 'j',
    LogicalKeyboardKey.keyK: 'k',
    LogicalKeyboardKey.keyL: 'l',
    LogicalKeyboardKey.keyM: 'm',
    LogicalKeyboardKey.keyN: 'n',
    LogicalKeyboardKey.keyO: 'o',
    LogicalKeyboardKey.keyP: 'p',
    LogicalKeyboardKey.keyQ: 'q',
    LogicalKeyboardKey.keyR: 'r',
    LogicalKeyboardKey.keyS: 's',
    LogicalKeyboardKey.keyT: 't',
    LogicalKeyboardKey.keyU: 'u',
    LogicalKeyboardKey.keyV: 'v',
    LogicalKeyboardKey.keyW: 'w',
    LogicalKeyboardKey.keyX: 'x',
    LogicalKeyboardKey.keyY: 'y',
    LogicalKeyboardKey.keyZ: 'z',
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.f1: 'f1',
    LogicalKeyboardKey.f2: 'f2',
    LogicalKeyboardKey.f3: 'f3',
    LogicalKeyboardKey.f4: 'f4',
    LogicalKeyboardKey.f5: 'f5',
    LogicalKeyboardKey.f6: 'f6',
    LogicalKeyboardKey.f7: 'f7',
    LogicalKeyboardKey.f8: 'f8',
    LogicalKeyboardKey.f9: 'f9',
    LogicalKeyboardKey.f10: 'f10',
    LogicalKeyboardKey.f11: 'f11',
    LogicalKeyboardKey.f12: 'f12',
    LogicalKeyboardKey.space: 'space',
  };

  @override
  bool operator ==(Object other) =>
      other is PickerShortcut &&
      other.key == key &&
      setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(modifiers));

  @override
  String toString() => 'PickerShortcut($serialized)';
}
