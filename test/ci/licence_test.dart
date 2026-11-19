import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards for the licence (PM decision D8, GPL-3.0): the licence file stays
/// the unchanged GNU text and the README keeps the licence notice.
void main() {
  test('LICENSE is the GNU GPL v3 text', () {
    final file = File('LICENSE');
    expect(file.existsSync(), isTrue, reason: 'LICENSE is missing');
    final text = file.readAsStringSync().trimLeft();
    expect(text, startsWith('GNU GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 3, 29 June 2007'));
  });

  test('README states the licence, the copyright and points to LICENSE', () {
    final readme = File('README.md').readAsStringSync();
    expect(
      readme,
      contains('Kusunga is licensed under the GNU General Public'),
    );
    expect(readme, contains('Copyright (C) 2026 William Nasoni'));
    expect(readme, contains('LICENSE'));
  });

  test('README and docs/licences.md say GPL-3.0-only, never "or later"', () {
    // PM decision R5 (2026-11-19): Kusunga is GPL-3.0-only.
    final readme = File('README.md').readAsStringSync();
    final licences = File('docs/licences.md').readAsStringSync();
    for (final entry in {
      'README.md': readme,
      'docs/licences.md': licences,
    }.entries) {
      expect(entry.value, contains('GPL-3.0-only'), reason: entry.key);
    }
    // Kusunga's own licence statements: README's Licence section, and every
    // licences.md line that names Kusunga's licence. Dependency rows (for
    // example LGPL "or later") are not about Kusunga and are not checked.
    final section = readme.split('## Licence').last;
    final own = [
      section,
      // Every prose line (not a table row) that mentions Kusunga.
      ...licences
          .split('\n')
          .where((l) => !l.startsWith('|') && l.contains('Kusunga')),
    ];
    for (final text in own) {
      expect(text.toLowerCase(), isNot(contains('any later version')));
      expect(text.toLowerCase(), isNot(contains('or-later')));
      expect(text.toLowerCase(), isNot(contains('or later')));
    }
    final ownLine = licences
        .split('\n')
        .firstWhere(
          (l) => l.startsWith('Kusunga is licensed'),
          orElse: () => '',
        );
    expect(ownLine, contains('GPL-3.0-only'));
  });

  test('licences.md names the SQLite3 Multiple Ciphers files it relies on', () {
    // Review note N1: these were covered only by directory or wildcard.
    final licences = File('docs/licences.md').readAsStringSync();
    for (final f in ['aes_hardware.c', 'memory_secure.c', 'libargon2.c']) {
      expect(licences, contains(f));
    }
    expect(licences, contains('src/ascon'));
    expect(licences, contains('aead.c'));
    // The headerless files, and the flag that says their licence is inferred.
    expect(licences, contains('permutations.c'));
    expect(licences, contains('round64.h'));
    expect(licences, contains('carry no licence header'));
  });

  test('SQLite3 Multiple Ciphers row and flag 1 do not overclaim', () {
    // Review note L1: flag 6 and the extensionfunctions.c row say some parts
    // are unclear or inferred, so no summary may say every part is clear.
    final lines = File('docs/licences.md').readAsLinesSync();
    final row = lines.firstWhere((l) => l.startsWith('| SQLite3 Multiple'));
    expect(row, isNot(contains('every part')));
    expect(row, contains('flag 1'));
    expect(row, contains('flag 6'));
    final flag1 = lines.firstWhere((l) => l.startsWith('1. '));
    expect(flag1, isNot(contains('Everything else is a clear')));
    expect(flag1, contains('flag 6'));
  });

  _testerGuards();
}

// ---------------------------------------------------------------------------
// Tester additions: pin the licence text and keep docs/licences.md in step
// with pubspec.yaml / pubspec.lock. Offline: the pinned hash is the SHA-256
// of https://www.gnu.org/licenses/gpl-3.0.txt, checked once by hand.
// ---------------------------------------------------------------------------

const _gplSha256 =
    '3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986';

/// Names under the top-level `dependencies:` of pubspec.yaml, minus the
/// Flutter SDK entry (its licence row is "Flutter SDK").
Set<String> _pubspecDirectDeps() {
  final names = <String>{};
  var inDeps = false;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    if (line.startsWith('dependencies:')) {
      inDeps = true;
      continue;
    }
    if (inDeps &&
        line.isNotEmpty &&
        !line.startsWith(' ') &&
        !line.startsWith('#')) {
      break;
    }
    final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (inDeps && m != null && m.group(1) != 'flutter') names.add(m.group(1)!);
  }
  return names;
}

/// package -> version for every direct main or direct overridden entry in
/// pubspec.lock.
Map<String, String> _lockDirectMain() {
  final out = <String, String>{};
  String? name;
  var direct = false;
  for (final line in File('pubspec.lock').readAsLinesSync()) {
    final n = RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line);
    if (n != null) {
      name = n.group(1);
      direct = false;
    }
    if (RegExp(r'dependency: "direct (main|overridden)"').hasMatch(line)) {
      direct = true;
    }
    final v = RegExp(r'^    version: "([^"]+)"').firstMatch(line);
    if (v != null && direct && name != null) out[name] = v.group(1)!;
  }
  return out;
}

/// First-column package token -> second-column version text of each table row.
Map<String, String> _licenceRows() {
  final rows = <String, String>{};
  var inTable = false;
  for (final line in File('docs/licences.md').readAsLinesSync()) {
    if (!line.startsWith('|')) {
      if (inTable) break; // only the first table lists packages
      continue;
    }
    inTable = true;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 4) continue;
    rows[cells[1].split(' ').first] = cells[2];
  }
  return rows;
}

void _testerGuards() {
  test('LICENSE bytes are exactly the pinned GNU GPL v3 text', () {
    final bytes = File('LICENSE').readAsBytesSync();
    expect(sha256.convert(bytes).toString(), _gplSha256);
    expect(bytes.length, 35149);
  });

  test('LICENSE has LF line endings (not rewritten by autocrlf)', () {
    expect(File('LICENSE').readAsStringSync(), isNot(contains('\r')));
  });

  test('.gitattributes keeps LICENSE out of line-ending conversion', () {
    // Git on Windows (core.autocrlf=true) would otherwise check LICENSE out
    // with CRLF and change its bytes and hash.
    final result = Process.runSync('git', ['check-attr', 'text', 'LICENSE']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString().trim(), endsWith('text: unset'));
    final file = File('.gitattributes');
    expect(file.existsSync(), isTrue, reason: '.gitattributes is missing');
    expect(
      file.readAsLinesSync().map((l) => l.trim()),
      contains('LICENSE -text'),
    );
  });

  test('README links LICENSE and docs/licences.md, both exist', () {
    final readme = File('README.md').readAsStringSync();
    expect(readme, contains('](LICENSE)'));
    expect(readme, contains('docs/licences.md'));
    expect(File('docs/licences.md').existsSync(), isTrue);
  });

  test('every direct dependency in pubspec.yaml has a licence row', () {
    final rows = _licenceRows();
    final deps = _pubspecDirectDeps();
    expect(deps, isNotEmpty, reason: 'pubspec parse found nothing');
    for (final d in deps) {
      expect(
        rows.keys,
        contains(d),
        reason: '$d has no row in docs/licences.md',
      );
    }
  });

  test('pubspec.yaml direct deps match pubspec.lock "direct main"', () {
    final lock = _lockDirectMain().keys.toSet();
    // flutter itself is "direct main" as an sdk package; ignore it.
    lock.remove('flutter');
    expect(lock, _pubspecDirectDeps());
  });

  test('versions in docs/licences.md match pubspec.lock', () {
    final rows = _licenceRows();
    _lockDirectMain().forEach((pkg, version) {
      if (pkg == 'flutter') return;
      expect(
        rows[pkg],
        version,
        reason: '$pkg: licences.md says ${rows[pkg]}, lock says $version',
      );
    });
  });

  test('licences.md has no row for a package that left pubspec.yaml', () {
    final known = {..._pubspecDirectDeps(), 'flutter'};
    for (final name in _licenceRows().keys) {
      // Package rows are lower-case identifiers; the others are named
      // components (SQLite3 Multiple Ciphers, SQLite, Flutter, Dart).
      if (RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
        expect(
          known,
          contains(name),
          reason: '$name is no longer a dependency',
        );
      }
    }
  });

  test(
    'SQLite and SQLite3 Multiple Ciphers rows match the sqlite3 package',
    () {
      final lock = _lockDirectMain()['sqlite3']!;
      final config = jsonDecode(
        File('.dart_tool/package_config.json').readAsStringSync(),
      );
      final entry = (config['packages'] as List).firstWhere(
        (p) => p['name'] == 'sqlite3',
      );
      final dir = Directory.fromUri(
        File(
          '.dart_tool/package_config.json',
        ).absolute.uri.resolve(entry['rootUri'] as String),
      );
      final lines = File('${dir.path}/CHANGELOG.md').readAsLinesSync();
      // Walk down from the locked version's section; the newest line that names
      // each library is the version that build bundles.
      var i = lines.indexWhere((l) => l.trim() == '## $lock');
      expect(
        i,
        isNonNegative,
        reason: 'no CHANGELOG section for sqlite3 $lock',
      );
      String? sqlite, mc;
      for (; i < lines.length && (sqlite == null || mc == null); i++) {
        sqlite ??= RegExp(
          r'SQLite (?:to |version |to version )?(3\.\d+\.\d+)',
        ).firstMatch(lines[i])?.group(1);
        mc ??= RegExp(
          r'Multiple Ciphers (?:to |version )?(\d+\.\d+\.\d+)',
        ).firstMatch(lines[i])?.group(1);
      }
      final rows = _licenceRows();
      expect(rows['SQLite3'], mc, reason: 'SQLite3 Multiple Ciphers row');
      expect(rows['SQLite'], sqlite, reason: 'SQLite row');
    },
  );

  test('Flutter and Dart rows match the SDK the project pins', () {
    final rows = _licenceRows();
    final readme = File('README.md').readAsStringSync();
    final m = RegExp(
      r'Flutter (\d+\.\d+\.\d+) \(Dart (\d+\.\d+\.\d+)\)',
    ).firstMatch(readme);
    expect(m, isNotNull, reason: 'README no longer names the SDK versions');
    expect(rows['Flutter'], m!.group(1));
    expect(rows['Dart'], m.group(2));
    // The Dart running this test is the pinned one.
    expect(Platform.version, startsWith(rows['Dart']!));
  });
}
