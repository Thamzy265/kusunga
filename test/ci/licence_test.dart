import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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
    // M1.10b: files new in SQLite3 Multiple Ciphers 2.7.x. The libsodium
    // ChaCha20/Poly1305 copy is ISC; libchacha20.c and csprng_entropy.c have
    // no licence text and are counted in flag 6.
    for (final f in [
      'src/chacha20',
      'libchacha20.c',
      'csprng_entropy.c',
      'btreecopyfile.c',
      'hwcheck.c',
      'ISC',
    ]) {
      expect(licences, contains(f), reason: f);
    }
    expect(flag6Line(licences), contains('libchacha20.c'));
    expect(flag6Line(licences), contains('csprng_entropy.c'));
    expect(licences, contains('src/ascon'));
    expect(licences, contains('aead.c'));
    // The headerless files, and the flag that says their licence is inferred.
    expect(licences, contains('permutations.c'));
    expect(licences, contains('round64.h'));
    expect(licences, contains('carry no licence header'));
    // Review note L5: mystdint.h also has no header and must stay listed,
    // in its table row and in flag 6.
    expect(licences, contains('mystdint.h'));
    final flag6 = flag6Line(licences);
    expect(flag6, contains('mystdint.h'));
    expect(flag6, contains('12 files in `src/ascon`'));
    // The count of headerless files is the same in the row, flag 1, flag 6.
    final rowAndFlags = licences
        .split('\n')
        .where(
          (l) =>
              l.startsWith('| SQLite3 Multiple Ciphers | 2.7.1') ||
              l.startsWith('1. ') ||
              l.startsWith('6. '),
        );
    for (final l in rowAndFlags) {
      expect(l, contains('16 files'));
    }
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

  test(
    'extensionfunctions.c: doc row and notice state the rule, not a claim',
    () {
      // Review cleanup (M1.9a R4): one cell said both "not compiled into
      // Kusunga's binaries" and "Windows binary not checked". The doc row and
      // the bundled notice give the rule and how it is enforced instead.
      final row = File('docs/licences.md').readAsLinesSync().firstWhere(
        (l) => l.startsWith('| extensionfunctions.c |'),
      );
      final notice = File('assets/licences/sqlite3mc.txt').readAsStringSync();
      final block = notice.substring(notice.indexOf('* extensionfunctions.c'));
      for (final (name, text) in [('doc row', row), ('notice', block)]) {
        for (final part in [
          'must not be compiled in',
          'tool/check_sqlite3mc.sh',
          // Review note L1 (M1.10b): all 4 desktop 2.7.1 binaries checked.
          'macOS and Windows 2.7.1 binaries checked 2026-11-24',
          'each shipped binary is checked again before release',
        ]) {
          expect(text, contains(part), reason: '$name: $part');
        }
        expect(text, isNot(contains('not compiled into')), reason: name);
        expect(text, isNot(contains('not checked')), reason: name);
      }
    },
  );

  test('flag 1 records the check of all 4 desktop 2.7.1 binaries', () {
    // Review note L1 (M1.10b): the reviewer ran tool/check_sqlite3mc.sh on
    // the 4 release files, each with the SHA-256 in the table, on
    // 2026-11-24. Flag 1 says so and keeps the rule for each release.
    final flag1 = File(
      'docs/licences.md',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('1. '));
    for (final file in [
      'libsqlite3mc.arm64.macos.dylib',
      'libsqlite3mc.x64.macos.dylib',
      'sqlite3mc.x64.windows.dll',
      'sqlite3mc.arm64.windows.dll',
    ]) {
      expect(flag1, contains(file), reason: file);
    }
    expect(flag1, contains('the SHA-256 in the table above'));
    expect(flag1, contains('by the reviewer on 2026-11-24'));
    expect(flag1, contains('before each release'));
    expect(flag1, isNot(contains('still to be checked')));
  });

  test('flag 5 names the loaded library as the version source, not the '
      'CHANGELOG', () {
    // Review note L2 (M1.10b): licence_test.dart reads the versions from the
    // library the test run loads; the sqlite3 CHANGELOG is not used.
    final flag5 = File(
      'docs/licences.md',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('5. '));
    expect(flag5, contains('sqlite3mc_version()'));
    expect(flag5, contains('sqlite3.version.libVersion'));
    expect(flag5, isNot(contains('CHANGELOG')));
  });

  test(
    'flag 4 covers the transitive packages that moved with sqlite3 3.9.2',
    () {
      // Review note L3 (M1.10b): hooks and record_use moved with sqlite3.
      final flag4 = File(
        'docs/licences.md',
      ).readAsLinesSync().firstWhere((l) => l.startsWith('4. '));
      for (final part in [
        'hooks 2.0.2 to 2.2.0',
        'record_use 0.6.0 to 1.1.1',
        'BSD-3-Clause (Dart project authors)',
        'checked by the developer on 2026-11-24',
      ]) {
        expect(flag4, contains(part), reason: part);
      }
      final lock = File('pubspec.lock').readAsStringSync();
      for (final (name, version) in [
        ('hooks', '2.2.0'),
        ('record_use', '1.1.1'),
      ]) {
        expect(
          RegExp(
            '  $name:\\n(?:    .*\\n|      .*\\n)*?    version: "$version"',
          ).hasMatch(lock),
          isTrue,
          reason: '$name $version is no longer the locked version',
        );
      }
    },
  );

  test('M1.10c: the nativeapi packages that ship have rows at the locked '
      'version, process and the moved packages are in flag 4', () {
    final rows = _licenceRows();
    final lock = File('pubspec.lock').readAsStringSync();
    String? locked(String name) => RegExp(
      '  $name:\\n(?:    .*\\n|      .*\\n)*?    version: "([^"]+)"',
    ).firstMatch(lock)?.group(1);
    for (final name in ['nativeapi', 'nativeapi_flutter', 'cnativeapi']) {
      expect(locked(name), isNotNull, reason: '$name is not in pubspec.lock');
      expect(rows[name], locked(name), reason: '$name row version');
    }
    final flag4 = File(
      'docs/licences.md',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('4. '));
    for (final (name, from) in [
      ('process', null),
      ('code_assets', '1.2.1'),
      ('native_toolchain_c', '0.19.2'),
      ('objective_c', '9.5.0'),
    ]) {
      final to = locked(name);
      expect(to, isNotNull, reason: '$name is not in pubspec.lock');
      expect(
        flag4,
        contains(from == null ? '$name $to' : '$name $from to $to'),
        reason: name,
      );
    }
    // The packages window_manager and tray_manager 0.5.x pulled in are gone.
    for (final gone in [
      'menu_base',
      'screen_retriever',
      'json_annotation',
      'shortid',
    ]) {
      expect(locked(gone), isNull, reason: '$gone is still locked');
      expect(flag4, contains(gone), reason: gone);
    }
  });

  test('csprng_entropy.c and libchacha20.c are stated as an inference, the '
      'same way in the row, the notice and flag 6', () {
    // Review note L4 (M1.10b): neither file has licence text. csprng_entropy.c
    // came out of the public-domain ChaCha20-Poly1305 code in an MIT project;
    // filelist.md at v2.7.1 puts the chacha20 directory under ISC, the
    // project LICENSE is MIT.
    final licences = File('docs/licences.md').readAsStringSync();
    final lines = licences.split('\n');
    final notice = File('assets/licences/sqlite3mc.txt').readAsStringSync();
    String block(String head) {
      final start = notice.indexOf(head);
      expect(start, isNot(-1), reason: head);
      final end = notice.indexOf('\n* ', start + 1);
      return notice.substring(start, end == -1 ? notice.length : end);
    }

    final places = {
      'csprng row': lines.firstWhere(
        (l) => l.startsWith('| ChaCha20 and Poly1305 (chacha20poly1305.c)'),
      ),
      'csprng notice': block('* ChaCha20 and Poly1305 (chacha20poly1305.c)'),
      'libchacha20 row': lines.firstWhere(
        (l) => l.startsWith('| ChaCha20 and Poly1305 from libsodium'),
      ),
      'libchacha20 notice': block(
        '* ChaCha20 and Poly1305 from libsodium (src/chacha20)',
      ),
    };
    final flag6 = flag6Line(licences);
    for (final (where, text) in [
      ('csprng row', places['csprng row']!),
      ('csprng notice', places['csprng notice']!),
      ('flag 6', flag6),
    ]) {
      expect(
        text,
        contains('csprng_entropy.c is public domain or MIT'),
        reason: where,
      );
    }
    for (final (where, text) in [
      ('libchacha20 row', places['libchacha20 row']!),
      ('libchacha20 notice', places['libchacha20 notice']!),
      ('flag 6', flag6),
    ]) {
      expect(text, contains('libchacha20.c is MIT or ISC'), reason: where);
      expect(text, contains('filelist.md'), reason: where);
    }
    // No place states either file's licence as a plain fact.
    for (final e in places.entries) {
      expect(
        e.value,
        isNot(
          contains(
            'libchacha20.c has no licence text and '
            'falls under',
          ),
        ),
        reason: e.key,
      );
      expect(
        e.value,
        isNot(contains('| Public domain. csprng')),
        reason: e.key,
      );
      expect(
        e.value,
        isNot(contains('Licence: Public domain. csprng')),
        reason: e.key,
      );
    }
  });

  _testerGuards();
}

// ---------------------------------------------------------------------------
// Tester additions: pin the licence text and keep docs/licences.md in step
// with pubspec.yaml / pubspec.lock. Offline: the pinned hash is the SHA-256
// of https://www.gnu.org/licenses/gpl-3.0.txt, checked once by hand.
// ---------------------------------------------------------------------------

/// Flag 6 of docs/licences.md: the files whose licence is inferred.
String flag6Line(String licences) => licences
    .split('\n')
    .firstWhere((l) => l.startsWith('6. '), orElse: () => '');

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

/// Package rows of the first table whose first cell says "(transitive".
Set<String> _transitiveRows() => {
  for (final line in File('docs/licences.md').readAsLinesSync())
    if (line.startsWith('| ') && line.split('|')[1].contains('(transitive'))
      line.split('|')[1].trim().split(' ').first,
};

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
    final locked = {
      for (final m in RegExp(
        r'^  ([a-z0-9_]+):$',
        multiLine: true,
      ).allMatches(File('pubspec.lock').readAsStringSync()))
        m.group(1)!,
    };
    for (final name in _licenceRows().keys) {
      // Package rows are lower-case identifiers; the others are named
      // components (SQLite3 Multiple Ciphers, SQLite, Flutter, Dart).
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) continue;
      // M1.10c: a transitive package that ships (nativeapi and friends) says
      // so in its row, and must still be in pubspec.lock.
      if (_transitiveRows().contains(name)) {
        expect(locked, contains(name), reason: '$name is no longer locked');
      } else {
        expect(
          known,
          contains(name),
          reason: '$name is no longer a dependency',
        );
      }
    }
  });

  test('SQLite and SQLite3 Multiple Ciphers rows match the loaded library', () {
    // M1.10b: the sqlite3 CHANGELOG is not a reliable source. 3.9.2 moved to
    // SQLite3 Multiple Ciphers 2.7.1, which is built on SQLite 3.54.1, but its
    // CHANGELOG names no SQLite version (the last one it names is 3.54.0).
    // The library the test run loads says which versions it is.
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final mc = db.select('SELECT sqlite3mc_version() AS v').single['v'];
    final rows = _licenceRows();
    expect(
      'SQLite3 Multiple Ciphers ${rows['SQLite3']}',
      mc,
      reason: 'SQLite3 Multiple Ciphers row',
    );
    expect(rows['SQLite'], sqlite3.version.libVersion, reason: 'SQLite row');
  });

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
