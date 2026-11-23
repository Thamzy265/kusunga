// M1.9a (AC1, flag 1 in docs/licences.md): tool/check_sqlite3mc.sh fails when
// a sqlite3mc binary contains extensionfunctions.c code (no licence upstream).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

const _script = 'tool/check_sqlite3mc.sh';

/// A stand-in binary: NUL-separated strings, like a C string table.
List<int> fake(List<String> strings) => [
  0,
  0,
  for (final s in strings) ...[...s.codeUnits, 0],
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sqlite3mc_check'));
  tearDown(() => dir.deleteSync(recursive: true));

  File binary(String name, List<String> strings) =>
      File('${dir.path}/$name')..writeAsBytesSync(fake(strings));

  ProcessResult run(List<String> args) => runBash(_script, args);

  const clean = ['sqlite_master', 'sqlite3mc_config', 'main', 'padding'];

  test('a clean sqlite3mc binary passes', () {
    final r = run([binary('clean.dll', clean).path]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('clean.dll'));
  });

  for (final name in [
    'padl',
    'padr',
    'padc',
    'strfilter',
    'charindex',
    'leftstr',
    'rightstr',
    'lower_quartile',
    'upper_quartile',
    'stdev',
    'variance',
    'replicate',
    'RegisterExtensionFunctions',
  ]) {
    test('fails when the extension function "$name" is in the binary', () {
      final r = run([
        binary('bad.dll', [...clean, name]).path,
      ]);
      expect(r.exitCode, isNot(0));
      expect('${r.stdout}${r.stderr}', contains('extensionfunctions'));
      expect('${r.stdout}${r.stderr}', contains(name));
    });
  }

  test('a word that only contains a short name does not fail it', () {
    final r = run([
      binary('ok.dll', [
        ...clean,
        'padlock',
        'unreplicated',
        'mystdevice',
      ]).path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('fails when the file is missing', () {
    final r = run(['${dir.path}/nope.dll']);
    expect(r.exitCode, isNot(0));
  });

  test('fails on an empty file or one that is not SQLite at all', () {
    final empty = File('${dir.path}/empty.dll')..writeAsBytesSync([]);
    expect(run([empty.path]).exitCode, isNot(0));
    final other = binary('other.dll', ['hello']);
    final r = run([other.path]);
    expect(r.exitCode, isNot(0));
    expect('${r.stdout}${r.stderr}', contains('not a SQLite'));
  });

  test('with several files, one bad one fails the run and names it', () {
    final good = binary('good.dll', clean);
    final bad = binary('bad.dll', [...clean, 'strfilter']);
    final r = run([good.path, bad.path]);
    expect(r.exitCode, isNot(0));
    expect('${r.stdout}${r.stderr}', contains('bad.dll'));
  });

  test('with no argument and nothing built it fails, never passes', () {
    final r = runBash(
      File(_script).absolute.path,
      [],
      workingDirectory: dir.path,
      environment: {'KUSUNGA_ROOT': dir.path},
    );
    expect(r.exitCode, isNot(0));
    expect('${r.stdout}${r.stderr}', contains('no sqlite3mc binary'));
  });

  test('the sqlite3mc binaries this machine has built are clean', () {
    final r = run([]);
    // No build here yet: nothing to check (the script says so and fails).
    if (r.exitCode != 0 && '${r.stderr}'.contains('no sqlite3mc binary')) {
      markTestSkipped('no sqlite3mc binary built on this machine');
      return;
    }
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('the script says how to run it on the Windows DLL', () {
    final text = File(_script).readAsStringSync();
    expect(text, contains('Windows'));
    expect(text, contains('sqlite3mc.dll'));
    expect(text, contains('Git Bash'));
  });
}
