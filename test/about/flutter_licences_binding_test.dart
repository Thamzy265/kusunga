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

String? _bindingPath() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) '$root/packages/flutter/lib/src/services/binding.dart',
    '/Users/williamnasoni/Developer/flutter/packages/flutter/lib/src/services/binding.dart',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
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
  return problems;
}

void main() {
  final path = _bindingPath();
  String real() => File(path!).readAsStringSync();

  test(
    'Flutter still registers its licences the way flutterNotices copies',
    () {
      expect(path, isNotNull, reason: 'Flutter SDK source not found');
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

    test('another separator', () {
      final m = real().replaceFirst("'-' * 80", "'=' * 80");
      expect(problemsIn(m), isNotEmpty);
    });
  });
}
