import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// M1.9b review round 3, R3: the binary guard's needle must be the real QA
/// switch argument in Swift, so renaming one without the other fails here.
final script = File('tool/mac_release_guards.sh').absolute.path;

void main() {
  group('R3 binary guard needle is the real QA switch', () {
    test('the script needle is inside SyntheticKeysSwitch.argument', () {
      final scriptText = File(script).readAsStringSync();
      final needle = RegExp(
        r'^needle="([^"]+)"',
        multiLine: true,
      ).firstMatch(scriptText)?.group(1);
      expect(needle, isNotNull, reason: 'needle= line not found in the script');
      final swift = File(
        'macos/Runner/TypedShortcutCore.swift',
      ).readAsStringSync();
      final argument = RegExp(
        r'static let argument = "([^"]+)"',
      ).firstMatch(swift)?.group(1);
      expect(argument, isNotNull, reason: 'argument constant not found');
      expect(argument, contains(needle));
    });
  });
}
