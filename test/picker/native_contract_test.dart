// Tester probes: the Dart side, the Swift side and the Windows C++ side must
// agree on key names, method names and answers. The Windows bridge is only
// compiled in CI, so a typo there would show up only on a PM's machine; these
// tests read the source files and compare.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/picker/picker_port.dart';
import 'package:kusunga/picker/shortcut.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('Mac key table (HotKeys.swift) against the Dart key list', () {
    final swift = read('macos/Runner/HotKeys.swift');
    final block = swift.substring(
      swift.indexOf('private static let codes'),
      swift.indexOf('static func keyCode'),
    );
    final entries = {
      for (final m in RegExp(r'"([a-z0-9]+)":\s*(\d+)').allMatches(block))
        m.group(1)!: int.parse(m.group(2)!),
    };

    test('exactly the keys Dart allows', () {
      expect(entries.keys.toSet(), PickerShortcut.allowedKeys);
    });

    test('no two keys share a code', () {
      expect(entries.values.toSet().length, entries.length);
    });

    test('US ANSI codes for the keys people pick most', () {
      // kVK_ANSI_V = 9, C = 8, K = 40, 1 = 18, 0 = 29, Space = 49, F1 = 122
      expect(entries['v'], 9);
      expect(entries['c'], 8);
      expect(entries['k'], 40);
      expect(entries['1'], 18);
      expect(entries['0'], 29);
      expect(entries['space'], 49);
      expect(entries['f1'], 122);
      expect(entries['f12'], 111);
    });
  });

  group('method names', () {
    final dart = read('lib/picker/channel_picker_port.dart');
    final sent = {
      for (final m in RegExp(r"_invoke<[^>]*>\(\s*'(\w+)'").allMatches(dart))
        m.group(1)!,
    };
    final swift = read('macos/Runner/PickerBridge.swift');
    final cpp = read('windows/runner/picker_bridge.cpp');

    test('Dart sends the ten methods we expect', () {
      expect(sent, {
        'registerShortcut',
        'unregisterShortcut',
        'openPicker',
        'closePicker',
        'paste',
        'showToast',
        'hideToast',
        'canPost',
        'permissionSnapshot',
        'requestPostAccess',
      });
    });

    for (final name in {
      'registerShortcut',
      'unregisterShortcut',
      'openPicker',
      'closePicker',
      'paste',
      'showToast',
      'hideToast',
      'canPost',
      'permissionSnapshot',
      'requestPostAccess',
    }) {
      test('Mac handles $name', () => expect(swift, contains('case "$name"')));
      test('Windows handles $name', () => expect(cpp, contains('"$name"')));
    }

    test('both sides send shortcutPressed and dismissed', () {
      for (final src in [swift, cpp]) {
        expect(src, contains('"shortcutPressed"'));
        expect(src, contains('"dismissed"'));
      }
    });
  });

  group('paste answers', () {
    final dartNames = {for (final o in PasteOutcome.values) o.name};
    final swift = read('macos/Runner/PasteFlow.swift');
    final cpp = read('windows/runner/picker_policy.h');

    test('every Mac answer is a name Dart understands', () {
      final enumBlock = RegExp(
        r'enum PasteResult: String \{([^}]*)\}',
      ).firstMatch(swift)!.group(1)!;
      final names = RegExp(
        r'case (\w+)',
      ).allMatches(enumBlock).map((m) => m.group(1)!);
      for (final n in names) {
        expect(dartNames, contains(n));
      }
    });

    test('every Windows answer string is a name Dart understands', () {
      final block = cpp.substring(cpp.indexOf('PasteResultName'));
      final names = RegExp(
        r'return "(\w+)";',
      ).allMatches(block).map((m) => m.group(1)!);
      expect(names, isNotEmpty);
      for (final n in names) {
        expect(dartNames, contains(n));
      }
    });
  });

  group('the paste marker', () {
    test(
      'Mac and Windows write the same marker name the design note gives',
      () {
        final mac =
            read('macos/Runner/ClipboardWatcher.swift') +
            read('macos/Runner/ClipboardBridge.swift');
        expect(mac, contains('com.wnasoni.kusunga.self'));
        final win =
            read('windows/runner/clipboard_policy.h') +
            read('windows/runner/clipboard_bridge.cpp');
        expect(win, contains('com.wnasoni.kusunga.self'));
      },
    );
  });
}
