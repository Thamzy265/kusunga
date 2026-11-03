import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards for build settings that a later edit could break without any other
/// test noticing (ADR 0003, design note "Rollout").
void main() {
  test('the Mac release build keeps the App Sandbox on (ADR 0003)', () {
    final plist = File('macos/Runner/Release.entitlements').readAsStringSync();
    expect(
      RegExp(
        r'<key>com\.apple\.security\.app-sandbox</key>\s*<true/>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test('the Mac debug build keeps the App Sandbox on too', () {
    final plist = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    expect(
      RegExp(
        r'<key>com\.apple\.security\.app-sandbox</key>\s*<true/>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test('the Mac CI job runs on the pinned macos-15 runner', () {
    final yaml = File('.github/workflows/check.yml').readAsStringSync();
    expect(yaml, contains('runs-on: macos-15'));
    expect(yaml, isNot(contains('macos-latest')));
  });
}
