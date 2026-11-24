// M1.10b: the library that encrypts the history database. sqlite3 3.9.2
// bundles SQLite3 Multiple Ciphers 2.7.1 on SQLite 3.54.1. Its CHANGELOG
// says 2.7.0, but the prebuilt library it downloads, with the SHA-256 the
// package checks, reports 2.7.1: the loaded library is the truth. Never 3.7.0
// to 3.8.x: they carry SQLite3 Multiple Ciphers 2.6.x, whose ChaCha20 code had a
// counter bug (docs/PLAN.md, M1.10).
//
// The library that a test run loads is the one the build hook downloaded for
// this machine, checked against the SHA-256 list inside the sqlite3 package.
// docs/licences.md records the 4 values for the desktop builds; this keeps
// them equal to the package's own list for the locked version.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// The sqlite3 version in pubspec.lock.
String _lockedSqlite3() {
  final lines = File('pubspec.lock').readAsLinesSync();
  final i = lines.indexOf('  sqlite3:');
  expect(i, isNonNegative, reason: 'no sqlite3 entry in pubspec.lock');
  for (final l in lines.skip(i + 1)) {
    final m = RegExp(r'^    version: "([^"]+)"').firstMatch(l);
    if (m != null) return m.group(1)!;
  }
  fail('no version for sqlite3 in pubspec.lock');
}

/// The root folder of the resolved sqlite3 package.
Directory _sqlite3Package() {
  final config = File('.dart_tool/package_config.json');
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final entry = (json['packages'] as List).firstWhere(
    (p) => p['name'] == 'sqlite3',
  );
  return Directory.fromUri(
    config.absolute.uri.resolve(entry['rootUri'] as String),
  );
}

void main() {
  test('the loaded library is SQLite 3.54.1 with SQLite3 Multiple Ciphers '
      '2.7.1', () {
    expect(sqlite3.version.libVersion, '3.54.1');
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    expect(
      db.select('SELECT sqlite3mc_version() AS v').single['v'],
      'SQLite3 Multiple Ciphers 2.7.1',
    );
  });

  test('pubspec.lock has sqlite3 3.9.2, never 3.7.0 to 3.8.x', () {
    final locked = _lockedSqlite3();
    expect(locked, '3.9.2');
    expect(locked, isNot(matches(RegExp(r'^3\.[78]\.'))));
  });

  test('docs/licences.md records the 4 desktop SQLite3 Multiple Ciphers '
      'SHA-256 values of the locked sqlite3 package', () {
    final package = _sqlite3Package();
    final hashes = File(
      '${package.path}/lib/src/hook/asset_hashes.dart',
    ).readAsStringSync();
    expect(
      hashes,
      contains("releaseTag = 'sqlite3-${_lockedSqlite3()}'"),
      reason: 'the hashes are for another release',
    );
    final doc = File('docs/licences.md').readAsStringSync();
    for (final file in [
      'libsqlite3mc.arm64.macos.dylib',
      'libsqlite3mc.x64.macos.dylib',
      'sqlite3mc.x64.windows.dll',
      'sqlite3mc.arm64.windows.dll',
    ]) {
      final m = RegExp(
        "'${RegExp.escape(file)}': '([0-9a-f]{64})'",
      ).firstMatch(hashes);
      expect(m, isNotNull, reason: '$file is not in the package list');
      final row = doc
          .split('\n')
          .firstWhere((l) => l.startsWith('| `$file`'), orElse: () => '');
      expect(row, contains(m!.group(1)!), reason: file);
    }
  });
}
