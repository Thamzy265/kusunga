import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every place that names the Flutter / Dart version the project builds with
/// says the same version (ADR 0008: "Every Flutter version pin changes
/// together"). CI is the source: a doc that disagrees with it is stale.
void main() {
  final versionPattern = r'(\d+\.\d+\.\d+)';

  /// The one `flutter-version:` both CI jobs use.
  String ciFlutter() {
    final text = File('.github/workflows/check.yml').readAsStringSync();
    final pins = [
      for (final m in RegExp(
        'flutter-version: *$versionPattern',
      ).allMatches(text))
        m.group(1)!,
    ];
    // The macOS and the Windows job.
    expect(pins, hasLength(2), reason: 'CI flutter-version pins: $pins');
    expect(pins.toSet(), hasLength(1), reason: 'CI jobs disagree: $pins');
    return pins.first;
  }

  /// Flutter and Dart from the first match of [pattern] in [path].
  (String, String) pair(String path, String pattern) {
    final m = RegExp(pattern).firstMatch(File(path).readAsStringSync());
    expect(m, isNotNull, reason: '$path no longer names the SDK versions');
    return (m!.group(1)!, m.group(2)!);
  }

  /// Version cell of the docs/licences.md row whose first cell is [name].
  String licenceRow(String name) {
    final row = File('docs/licences.md').readAsLinesSync().firstWhere(
      (l) => l.startsWith('| $name |'),
      orElse: () => '',
    );
    expect(row, isNotEmpty, reason: 'docs/licences.md has no $name row');
    return row.split('|')[2].trim();
  }

  test('CLAUDE.md, README and docs/licences.md name the CI Flutter and one '
      'Dart', () {
    final flutter = ciFlutter();
    final (claudeFlutter, claudeDart) = pair(
      'CLAUDE.md',
      'Stack: Flutter $versionPattern / Dart $versionPattern',
    );
    final (readmeFlutter, readmeDart) = pair(
      'README.md',
      'Flutter $versionPattern \\(Dart $versionPattern\\)',
    );
    final licencesFlutter = licenceRow('Flutter SDK');
    final licencesDart = licenceRow('Dart SDK');

    expect(claudeFlutter, flutter, reason: 'CLAUDE.md Stack vs CI');
    expect(readmeFlutter, flutter, reason: 'README Requirements vs CI');
    expect(licencesFlutter, flutter, reason: 'docs/licences.md vs CI');

    expect(readmeDart, claudeDart, reason: 'README Dart vs CLAUDE.md');
    expect(
      licencesDart,
      claudeDart,
      reason: 'docs/licences.md Dart vs CLAUDE.md',
    );
  });

  test('the Windows runner guide names the CI Flutter', () {
    final text = File('docs/ci/windows-runner.md').readAsStringSync();
    final m = RegExp('downloads Flutter $versionPattern').firstMatch(text);
    expect(m, isNotNull, reason: 'windows-runner.md no longer names Flutter');
    expect(m!.group(1), ciFlutter());
  });
}
