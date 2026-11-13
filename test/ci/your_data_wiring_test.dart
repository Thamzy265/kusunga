// M1.8: Delete everything in a debug data profile must never delete the
// default key it shares with the real history (brief, 2026-11-12), and
// never touch launch at login there (lead ruling G3). A guard on the app's
// wiring, which unit tests of DataEraser can't see.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final main = File('lib/main.dart').readAsStringSync();

  String arm(String pattern) {
    final start = main.indexOf(pattern);
    expect(start, isNonNegative, reason: pattern);
    final end = main.indexOf('),', start);
    return main.substring(start, end);
  }

  test('a profile erases only its folder, with no key', () {
    final profile = arm('ActiveDataProfile() =>');
    expect(profile, contains('ProfileEraseTarget('));
    expect(profile, isNot(contains('keys')));
  });

  test('a rejected profile erases nothing on disk', () {
    expect(
      main,
      contains('RejectedDataProfile() => const NoDataEraseTarget()'),
    );
  });

  test('only the default data deletes the key', () {
    expect(arm('NoDataProfile() =>'), contains('DefaultEraseTarget('));
    expect(RegExp('DefaultEraseTarget\\(').allMatches(main).length, 1);
  });
}
