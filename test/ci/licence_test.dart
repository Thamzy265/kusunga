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
    expect(readme, contains('Kusunga is licensed under the GNU GPL v3.0'));
    expect(readme, contains('Copyright (C) 2026 William Nasoni'));
    expect(readme, contains('LICENSE'));
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

/// package -> version for every `dependency: "direct main"` in pubspec.lock.
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
    if (line.contains('dependency: "direct main"')) direct = true;
    final v = RegExp(r'^    version: "([^"]+)"').firstMatch(line);
    if (v != null && direct && name != null) out[name] = v.group(1)!;
  }
  return out;
}

/// First-column package token -> second-column version text of each table row.
Map<String, String> _licenceRows() {
  final rows = <String, String>{};
  for (final line in File('docs/licences.md').readAsLinesSync()) {
    if (!line.startsWith('|')) continue;
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
}
