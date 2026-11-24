// M1.10a (tester): gaps in test/ci/sdk_version_pins_test.dart.
//  * That test only checks that the pins AGREE with CI; this one also checks
//    CI itself names a full release (not a range or branch), that every
//    flutter-action step is pinned, and that no operational file still names
//    an older Flutter than CI.
//  * Its `hasLength(2)` fails for a third job, which is loud but names the
//    wrong problem; here every flutter-action step is checked on its own.
// Abuse case "an attacker changes a Flutter tag": the version is a full
// x.y.z and the action is a commit hash, so neither floats.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _ci = File('.github/workflows/check.yml').readAsStringSync();

/// The `flutter-version:` values, with or without quotes.
List<String> ciVersions() => [
  for (final m in RegExp(
    r'''flutter-version:\s*["']?([^"'\s#]+)["']?''',
  ).allMatches(_ci))
    m.group(1)!,
];

/// Whether version [need] is not above [have] (both x.y.z).
bool notAbove(List<int> need, List<int> have) {
  for (var i = 0; i < 3; i++) {
    if (have[i] != need[i]) return have[i] > need[i];
  }
  return true;
}

void main() {
  test('every flutter-action step has one flutter-version, a full x.y.z', () {
    final steps = RegExp('subosito/flutter-action@').allMatches(_ci).length;
    final versions = ciVersions();
    expect(steps, greaterThanOrEqualTo(2));
    expect(versions, hasLength(steps), reason: 'a step has no version: $_ci');
    for (final v in versions) {
      expect(v, matches(RegExp(r'^\d+\.\d+\.\d+$')), reason: 'not a release');
    }
    expect(versions.toSet(), hasLength(1));
  });

  test('CI uses the stable channel, never master or main', () {
    final channels = [
      for (final m in RegExp(r'channel:\s*["\x27]?(\w+)').allMatches(_ci))
        m.group(1)!,
    ];
    expect(channels, isNotEmpty);
    expect(channels.toSet(), {'stable'});
  });

  test('every `uses:` in every workflow is a 40-hex commit, not a tag', () {
    final bad = <String>[];
    for (final f in Directory('.github/workflows').listSync()) {
      if (f is! File || !f.path.endsWith('.yml')) continue;
      for (final m in RegExp(
        r'uses:\s*(\S+)',
      ).allMatches(f.readAsStringSync())) {
        final ref = m.group(1)!;
        if (!RegExp(r'@[0-9a-f]{40}$').hasMatch(ref)) bad.add('${f.path} $ref');
      }
    }
    expect(bad, isEmpty);
  });

  test('no operational file names a Flutter version other than the CI one', () {
    final ci = ciVersions().first;
    // Files a person reads to set up or run the project. History (docs/qa,
    // docs/status.md, ADRs, design notes, slides, PLAN) may name old ones.
    final files = <File>[
      File('README.md'),
      File('CLAUDE.md'),
      File('docs/licences.md'),
      for (final dir in ['docs/ci', '.github', 'tool'])
        if (Directory(dir).existsSync())
          ...Directory(dir).listSync(recursive: true).whereType<File>(),
    ];
    final stale = <String>[];
    for (final f in files) {
      var n = 0;
      for (final line in f.readAsLinesSync()) {
        n++;
        for (final m in RegExp(r'Flutter (\d+\.\d+\.\d+)').allMatches(line)) {
          if (m.group(1) != ci) stale.add('${f.path}:$n ${m.group(0)}');
        }
      }
    }
    expect(stale, isEmpty);
  });

  test('the Dart and Flutter the lockfile needs are not above what CI '
      'installs', () {
    final lock = File('pubspec.lock').readAsStringSync();
    List<int> lower(String sdk) {
      final m = RegExp(
        '^  $sdk: ">=(\\d+)\\.(\\d+)\\.(\\d+)',
        multiLine: true,
      ).firstMatch(lock);
      expect(m, isNotNull, reason: 'pubspec.lock has no $sdk lower bound');
      return [for (var i = 1; i <= 3; i++) int.parse(m!.group(i)!)];
    }

    // CI installs the Flutter in check.yml. Its Dart is the one CLAUDE.md
    // names (sdk_version_pins_test and licence_test tie that to the SDK that
    // runs the tests).
    final dart = RegExp(
      r'Stack: Flutter \d+\.\d+\.\d+ / Dart (\d+\.\d+\.\d+)',
    ).firstMatch(File('CLAUDE.md').readAsStringSync());
    expect(dart, isNotNull, reason: 'CLAUDE.md no longer names the Dart');
    for (final (sdk, need, have) in [
      ('Flutter', lower('flutter'), ciVersions().first),
      ('Dart', lower('dart'), dart!.group(1)!),
    ]) {
      expect(
        notAbove(need, have.split('.').map(int.parse).toList()),
        isTrue,
        reason: 'lock needs $sdk $need, CI has $have',
      );
    }
  });
}
