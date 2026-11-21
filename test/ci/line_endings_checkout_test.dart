// Windows CI green (group D), tester: the `* text=auto eol=lf` rule, played
// end to end in a throw-away repository with core.autocrlf=true (what Git on
// Windows does by default). Text comes out with LF, and binaries (a PNG, whose
// signature even holds CR LF, an SQLite file, a font) come out byte for byte.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Real shapes: the PNG signature (89 50 4E 47 0D 0A 1A 0A) then an IHDR
/// chunk length, the "SQLite format 3" header, and a TrueType header with a
/// CR LF inside the table data.
final _binaries = {
  'icon.png': Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, //
    0x48, 0x44, 0x52, 0x0D, 0x0A, 0x0D, 0x0A,
  ]),
  'kusunga.db': Uint8List.fromList([
    ...'SQLite format 3'.codeUnits,
    0,
    0x10,
    0x00,
    0x0D,
    0x0A,
    0x0A,
  ]),
  'font.ttf': Uint8List.fromList([0, 1, 0, 0, 0, 0x0D, 0x0A, 0x0D, 0x0A, 0]),
};

void main() {
  late Directory dir;
  final gitattributes = File('.gitattributes').readAsStringSync();

  ProcessResult git(Directory at, List<String> args) {
    final r = Process.runSync(
      'git',
      [
        '-c',
        'core.autocrlf=true',
        '-c',
        'user.name=t',
        '-c',
        'user.email=t@example.invalid',
        '-c',
        'commit.gpgsign=false',
        ...args,
      ],
      workingDirectory: at.path,
      environment: {'GIT_CONFIG_NOSYSTEM': '1'},
    );
    expect(r.exitCode, 0, reason: '${args.join(' ')}: ${r.stderr}');
    return r;
  }

  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_tester_eol_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('with core.autocrlf=true, text is written with LF and binaries are '
      'untouched, in the index and in a fresh clone', () {
    final src = Directory(p.join(dir.path, 'src'))..createSync();
    File(p.join(src.path, '.gitattributes')).writeAsStringSync(gitattributes);
    File(p.join(src.path, 'a.dart')).writeAsBytesSync('a\r\nb\r\n'.codeUnits);
    File(
      p.join(src.path, 'b.xcconfig'),
    ).writeAsBytesSync('A = 1\r\n'.codeUnits);
    for (final e in _binaries.entries) {
      File(p.join(src.path, e.key)).writeAsBytesSync(e.value);
    }
    git(src, ['init', '-q']);
    git(src, ['add', '-A']);
    git(src, ['commit', '-q', '-m', 'x']);

    expect(
      Process.runSync(
        'git',
        ['cat-file', 'blob', 'HEAD:a.dart'],
        workingDirectory: src.path,
        stdoutEncoding: null,
      ).stdout,
      'a\nb\n'.codeUnits,
      reason: 'CRLF text is stored as LF',
    );
    final clone = Directory(p.join(dir.path, 'clone'));
    git(dir, ['clone', '-q', src.path, clone.path]);
    expect(
      File(p.join(clone.path, 'a.dart')).readAsBytesSync(),
      'a\nb\n'.codeUnits,
      reason: 'checked out with LF, not CRLF',
    );
    expect(
      File(p.join(clone.path, 'b.xcconfig')).readAsBytesSync(),
      'A = 1\n'.codeUnits,
    );
    for (final e in _binaries.entries) {
      expect(
        File(p.join(clone.path, e.key)).readAsBytesSync(),
        e.value,
        reason: '${e.key} must not be treated as text',
      );
    }
    git(clone, ['diff', '--exit-code', '--quiet']);
  });

  test('the repository\'s own binaries are not text to Git (so no checkout '
      'can change them)', () {
    final r = Process.runSync('git', ['ls-files', '--eol']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final rows = (r.stdout as String)
        .trim()
        .split('\n')
        .map((l) => l.split(RegExp(r'\s+')))
        .toList();
    // "i/-text w/-text attr/text=auto eol=lf <TAB> path"
    bool binary(List<String> row) => row[0] == 'i/-text';
    final binaries = rows.where(
      (r) => RegExp(r'\.(png|ico|icns|ttf|otf|db|jpg|zip)$').hasMatch(r.last),
    );
    expect(binaries, isNotEmpty);
    expect(binaries.where((r) => !binary(r)).map((r) => r.last), isEmpty);
    expect(
      rows
          .where((r) => r[0] == 'i/crlf' || r[0] == 'i/mixed')
          .map((r) => r.last),
      isEmpty,
      reason: 'no text file has CR LF in the index',
    );
  });
}
