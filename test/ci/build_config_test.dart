import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_text.dart';

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

  test('both Mac builds may read and write only the file the user picks '
      '(M1.8 D1 A): user-selected read-write, nothing wider', () {
    for (final path in [
      'macos/Runner/Release.entitlements',
      'macos/Runner/DebugProfile.entitlements',
    ]) {
      final plist = File(path).readAsStringSync();
      expect(
        RegExp(
          r'<key>com\.apple\.security\.files\.user-selected\.read-write</key>'
          r'\s*<true/>',
        ).hasMatch(plist),
        isTrue,
        reason: path,
      );
      for (final wider in [
        'files.all',
        'files.downloads',
        'temporary-exception.files',
        'assets.',
        'files.user-selected.executable',
      ]) {
        expect(plist, isNot(contains(wider)), reason: '$path: $wider');
      }
    }
  });

  test('the Mac CI job runs on the pinned macos-15 runner', () {
    final yaml = File('.github/workflows/check.yml').readAsStringSync();
    expect(yaml, contains('runs-on: macos-15'));
    expect(yaml, isNot(contains('macos-latest')));
  });

  test('Windows CI: the build runs even when the tests fail, and the job '
      'still fails then', () {
    final yaml = readSource('.github/workflows/check.yml');
    final windows = yaml.substring(yaml.indexOf('\n  windows:'));
    final build = RegExp(
      r'- run: flutter build windows[^\n]*\n\s+if: \$\{\{ !cancelled\(\) \}\}',
    );
    expect(windows, matches(build));
    // A failed test step still fails the job: nothing swallows its failure.
    expect(yaml, isNot(contains('continue-on-error')));
  });

  test('both CI jobs get packages with --enforce-lockfile, so CI fails on a '
      'lock that does not match pubspec.yaml or a package hash instead of '
      'rewriting pubspec.lock (M1.10a review R3)', () {
    final yaml = readSource('.github/workflows/check.yml');
    final macos = yaml.indexOf('\n  macos:');
    final windows = yaml.indexOf('\n  windows:');
    expect(macos, greaterThan(0));
    expect(windows, greaterThan(macos));
    final jobs = {
      'macos': yaml.substring(macos, windows),
      'windows': yaml.substring(windows),
    };
    for (final job in jobs.entries) {
      expect(
        RegExp(
          r'^\s+- run: flutter pub get --enforce-lockfile$',
          multiLine: true,
        ).allMatches(job.value),
        hasLength(1),
        reason: '${job.key} job',
      );
    }
    // No other step gets or upgrades packages without the flag.
    final gets = [
      for (final m in RegExp(
        r'\b(flutter|dart) pub (get|upgrade|downgrade)\b[^\n]*',
      ).allMatches(yaml))
        m.group(0)!,
    ];
    expect(gets, hasLength(2));
    expect(gets, everyElement(contains('--enforce-lockfile')));
  });
}
