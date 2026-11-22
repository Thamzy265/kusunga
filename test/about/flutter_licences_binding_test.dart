// R11 (M1.9a): `flutterNotices` is a hand copy of Flutter's private
// `ServicesBinding._addLicenses`, which `KusungaBinding.initLicenses` replaces.
// This reads the pinned Flutter's own source and fails when that source no
// longer matches what the copy assumes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _recheck =
    'Flutter changed how it registers its licences: flutterNotices '
    '(lib/about/flutter_notices.dart) and KusungaBinding must be re-checked '
    'against the new Flutter, or the build ships without the Flutter and '
    'engine notices.';

/// The flutter tool exports FLUTTER_ROOT to every test run. If it is missing
/// this fails with a clear message; it does not skip.
String _bindingPath() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError(
      'FLUTTER_ROOT is not set: run the tests with flutter test or '
      './tool/check.sh, which export it.',
    );
  }
  final path = '$root/packages/flutter/lib/src/services/binding.dart';
  if (!File(path).existsSync()) {
    throw StateError('Flutter SDK source not found at $path');
  }
  return path;
}

/// What is wrong with [source], one line each; empty when it matches.
List<String> problemsIn(String source) {
  final problems = <String>[];
  final init = RegExp(
    r'void initLicenses\(\)\s*\{([^}]*)\}',
  ).firstMatch(source)?.group(1)?.trim();
  if (init != 'LicenseRegistry.addLicense(_addLicenses);') {
    problems.add('initLicenses body is now: ${init ?? '(not found)'}');
  }
  final start = source.indexOf('Stream<LicenseEntry> _addLicenses()');
  final end = source.indexOf('_parseLicenses(String', start);
  final add = start < 0 || end < 0 ? '' : source.substring(start, end);
  for (final (what, needle) in [
    ("loads 'NOTICES.Z'", "rootBundle.load('NOTICES.Z')"),
    ('gzip decodes', 'gzip.decode'),
    ('utf8 decodes', 'utf8.decode'),
  ]) {
    if (!add.contains(needle)) problems.add('_addLicenses no longer $what');
  }
  if (!source.contains(r"'\n${'-' * 80}\n'")) {
    problems.add('the 80-dash separator is gone or changed');
  }
  final parseStart = source.indexOf('_parseLicenses(String');
  final parseEnd = parseStart < 0 ? -1 : source.indexOf('\n  }\n', parseStart);
  final parse = parseEnd < 0 ? '' : source.substring(parseStart, parseEnd);
  for (final needle in [
    "indexOf('\\n\\n')",
    "substring(0, split).split('\\n')",
    'substring(split + 2)',
  ]) {
    if (!parse.contains(needle)) {
      problems.add('_parseLicenses no longer has: $needle');
    }
  }
  return problems;
}

void main() {
  String real() => File(_bindingPath()).readAsStringSync();

  test(
    'Flutter still registers its licences the way flutterNotices copies',
    () {
      expect(problemsIn(real()), isEmpty, reason: _recheck);
    },
  );

  group('the check fails on a changed copy of the source', () {
    test('a second registration in initLicenses', () {
      final m = real().replaceFirst(
        'LicenseRegistry.addLicense(_addLicenses);',
        'LicenseRegistry.addLicense(_addLicenses);\n    registerMore();',
      );
      expect(problemsIn(m), isNotEmpty);
    });

    test('another asset name', () {
      final m = real().replaceFirst("'NOTICES.Z'", "'NOTICES.br'");
      expect(problemsIn(m), isNotEmpty);
    });

    test('no gzip', () {
      expect(
        problemsIn(real().replaceAll('gzip.decode', 'zlib.decode')),
        isNotEmpty,
      );
    });

    test('a changed split of package names from text', () {
      final m = real().replaceFirst(
        'substring(split + 2)',
        'substring(split + 1)',
      );
      expect(problemsIn(m), isNotEmpty);
    });

    test('another blank-line split', () {
      final m = real().replaceFirst("indexOf('\\n\\n')", "indexOf('\\n')");
      expect(problemsIn(m), isNotEmpty);
    });

    test('another separator', () {
      final m = real().replaceFirst("'-' * 80", "'=' * 80");
      expect(problemsIn(m), isNotEmpty);
    });
  });
}
