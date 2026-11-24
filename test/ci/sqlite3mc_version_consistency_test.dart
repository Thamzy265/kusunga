// M1.10b (tester): the version text, the notices and the SHA-256 table agree
// with the library the build bundles, in the places a user or a release
// check reads them. Complements test/data/bundled_sqlite_test.dart (lock and
// hash values) and test/ci/licence_test.dart (licences.md wording).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/licences.dart';
import 'package:sqlite3/sqlite3.dart';

const _files = [
  'libsqlite3mc.arm64.macos.dylib',
  'libsqlite3mc.x64.macos.dylib',
  'sqlite3mc.x64.windows.dll',
  'sqlite3mc.arm64.windows.dll',
];

String _read(String path) => File(path).readAsStringSync();

/// Rows of the SHA-256 table in docs/licences.md: file -> value cell.
Map<String, String> _hashRows() {
  final rows = <String, String>{};
  for (final line in _read('docs/licences.md').split('\n')) {
    final m = RegExp(r'^\| `([^`]+)` \| (.*?) \|$').firstMatch(line);
    if (m != null && m.group(1)!.contains('sqlite3mc')) {
      rows[m.group(1)!] = m.group(2)!;
    }
  }
  return rows;
}

void main() {
  test('the SHA-256 table has exactly the 4 desktop files, each one a '
      'lower-case 64-digit value, no two the same', () {
    final rows = _hashRows();
    expect(rows.keys.toSet(), _files.toSet());
    final values = <String>[];
    for (final e in rows.entries) {
      final m = RegExp(r'^`?([0-9a-f]{64})`?$').firstMatch(e.value.trim());
      expect(m, isNotNull, reason: '${e.key}: "${e.value}"');
      values.add(m!.group(1)!);
    }
    expect(values.toSet(), hasLength(4), reason: 'a value is repeated');
  });

  test('every first-line version in a bundled notice is the loaded '
      'library\'s', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final mc = db.select('SELECT sqlite3mc_version() AS v').single['v'];
    expect(mc, 'SQLite3 Multiple Ciphers 2.7.1');
    final mcNotice = _read(sqlite3mcNoticesAsset);
    expect(mcNotice.split('\n').first, startsWith('$mc and the parts'));
    // "built on SQLite x" in the same notice is the loaded SQLite.
    expect(mcNotice, contains('built on SQLite ${sqlite3.version.libVersion}'));
    expect(
      _read(sqliteNoticeAsset).split('\n').first,
      'SQLite ${sqlite3.version.libVersion}',
    );
  });

  test('nothing a user can read still names the old library versions', () {
    // The licence page texts and every Dart string shipped in the app. (The
    // history of this change in docs/ and QA notes may name them.)
    final shipped = [
      File(sqlite3mcNoticesAsset),
      File(sqliteNoticeAsset),
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];
    for (final f in shipped) {
      final text = f.readAsStringSync();
      for (final old in ['3.53.4', '2.5.0', '2.7.0', 'SQLite 3.53']) {
        expect(text, isNot(contains(old)), reason: '${f.path}: $old');
      }
    }
    // The ui spec the licence page is built from says the new versions too.
    final ui = _read('docs/ui/about-and-licences.md');
    expect(ui, isNot(contains('3.53.4')));
  });

  test('the text of each new part in docs/licences.md is also in the '
      'notice the licence page shows', () {
    final notice = _read(sqlite3mcNoticesAsset);
    for (final part in [
      'src/chacha20',
      'libchacha20.c',
      'csprng_entropy.c',
      'btreecopyfile.c',
      'hwcheck.c',
      'ISC License',
      'Frank Denis',
      'chacha20_ref.c',
      'D. J. Bernstein',
    ]) {
      expect(notice, contains(part), reason: part);
    }
    // The ISC text is complete: permission line and the warranty line.
    expect(
      notice,
      contains('Permission to use, copy, modify, and/or distribute'),
    );
    expect(notice, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    expect(notice, contains('OR IN CONNECTION WITH THE USE OR PERFORMANCE'));
  });

  test('the licence page model shows the ISC text and the new parts as '
      'paragraphs, ISC kept as written (indented block, own line breaks)', () {
    final entry = NoticeEntry(const [
      'SQLite3 Multiple Ciphers',
    ], _read(sqlite3mcNoticesAsset));
    final text = entry.paragraphs.map((p) => p.text).join('\n\n');
    expect(text, contains('ISC License'));
    expect(text, contains('Frank Denis'));
    expect(text, contains('csprng_entropy.c'));
    expect(text, contains('hwcheck.c'));
    // The copyright holder line keeps its own line (not run into the text).
    final lines = text.split('\n');
    expect(lines.any((l) => l.startsWith('Copyright (c) 2013-2026')), isTrue);
  });

  test('the notices and licences.md are LF only and the fixture files are '
      'marked binary (nothing rewrites them on Windows)', () {
    for (final f in [
      sqlite3mcNoticesAsset,
      sqliteNoticeAsset,
      'docs/licences.md',
    ]) {
      expect(_read(f), isNot(contains('\r')), reason: f);
    }
    for (final f in Directory(
      'test/data/fixtures',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.db'))) {
      final r = Process.runSync('git', ['check-attr', 'binary', f.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout.toString().trim(),
        endsWith('binary: set'),
        reason: f.path,
      );
      final t = Process.runSync('git', ['check-attr', 'eol', f.path]);
      // A binary file has no end-of-line conversion at all.
      expect(t.stdout.toString(), isNot(contains('eol: crlf')));
    }
  });
}
