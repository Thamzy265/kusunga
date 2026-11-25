import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.10c (lead decision, after F4): `tool/mac_release_guards.sh` never prints
/// a Team ID, whatever shell options the caller exports. With `xtrace` in an
/// exported SHELLOPTS, bash would start the guard tracing every command it
/// runs, Team ID included: the codesign details it reads, the team it
/// compares, and the signing example file it scans. Every mode is run here
/// with xtrace exported, and the fake Team ID must appear 0 times in stdout
/// and stderr, while the verdict stays the same. A fake `codesign` first on the
/// PATH reads the "signature" from marker files, so nothing is signed and no
/// real identity or Team ID is used.
const script = 'tool/mac_release_guards.sh';

// `.fake_team` holds the Team ID (no file: not signed at all). It is a bash
// script, so the exported options reach it too: it turns them off, as the
// real tool is not a script.
const _fakeCodesign = r'''#!/usr/bin/env bash
set +fx
target="${@: -1}"
case "$1" in
  --verify)
    [ -e "$target/.fake_team" ] || { echo "$target: code object is not signed at all" >&2; exit 1; }
    exit 0 ;;
  -dv)
    [ -e "$target/.fake_team" ] || { echo "$target: code object is not signed at all" >&2; exit 1; }
    echo "Executable=$target" >&2
    echo "TeamIdentifier=$(cat "$target/.fake_team")" >&2
    exit 0 ;;
esac
echo "fake codesign: unexpected arguments $*" >&2
exit 3
''';

// Sentinels no message of the script could contain by chance.
const _appTeam = 'ZZXTRACE01';
const _otherTeam = 'ZZXTRACE02';

/// What `set -x; export SHELLOPTS` in the caller's shell leaves behind.
const _xtrace = 'braceexpand:hashall:interactive-comments:xtrace';

void main() {
  late Directory tmp;
  late Directory bin;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('guard xtrace');
    bin = Directory('${tmp.path}/bin')..createSync();
    final fake = File('${bin.path}/codesign')..writeAsStringSync(_fakeCodesign);
    Process.runSync('chmod', ['+x', fake.path]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult run(List<String> args) => runBash(
    script,
    args,
    environment: {
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'SHELLOPTS': _xtrace,
    },
  );

  /// How often either fake Team ID appears in all the output.
  int teamIds(ProcessResult r) {
    final all = '${r.stdout}${r.stderr}';
    return _appTeam.allMatches(all).length + _otherTeam.allMatches(all).length;
  }

  final skip = skipOnWindows('codesign and the Mac release run on macOS only');

  test('an exported xtrace really starts bash tracing (so the tests below '
      'are not vacuous)', () {
    final probe = Process.runSync(
      findBash(),
      ['-c', 'echo traced-probe'],
      environment: {'SHELLOPTS': _xtrace},
    );
    expect('${probe.stderr}', contains('+ echo traced-probe'));
  }, skip: skip);

  group('frameworks', () {
    late Directory app;

    void signed(String path, String team) {
      final dir = Directory('${app.path}/$path')..createSync(recursive: true);
      File('${dir.path}/.fake_team').writeAsStringSync(team);
    }

    setUp(() {
      app = Directory('${tmp.path}/Kusunga.app')..createSync();
      signed('', _appTeam);
      for (final name in ['sqlite3mc', 'cnativeapi', 'App']) {
        signed('Contents/Frameworks/$name.framework', _appTeam);
      }
    });

    test('a good app passes and the Team ID appears 0 times', () {
      final r = run(['frameworks', app.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(teamIds(r), 0);
    }, skip: skip);

    test('a framework of another team fails and neither Team ID appears', () {
      signed('Contents/Frameworks/cnativeapi.framework', _otherTeam);
      final r = run(['frameworks', app.path]);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('cnativeapi.framework'));
      expect(teamIds(r), 0);
    }, skip: skip);

    test('an ad-hoc app fails and the Team ID of its frameworks does not '
        'appear', () {
      signed('', 'not set');
      final r = run(['frameworks', app.path]);
      expect(r.exitCode, 1);
      expect(teamIds(r), 0);
    }, skip: skip);
  });

  group('xcconfig', () {
    File example(String extra) =>
        File('${tmp.path}/Local.xcconfig.example')..writeAsStringSync(
          '// Signing for local Release builds.\n'
          'DEVELOPMENT_TEAM = $_appTeam\n'
          'CODE_SIGN_STYLE = Automatic\n'
          'CODE_SIGN_IDENTITY = Apple Development\n'
          '$extra',
        );

    test('the signing example passes and its Team ID appears 0 times', () {
      final r = run(['xcconfig', example('').path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(teamIds(r), 0);
    }, skip: skip);

    test('a file with a -D flag fails and its Team ID appears 0 times', () {
      final r = run([
        'xcconfig',
        example('OTHER_SWIFT_FLAGS = -DDEBUG\n').path,
      ]);
      expect(r.exitCode, 1);
      expect(teamIds(r), 0);
    }, skip: skip);

    test('a file that sets another key fails and its Team ID appears 0 '
        'times', () {
      final r = run(['xcconfig', example('SWIFT_VERSION = 5.0\n').path]);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('SWIFT_VERSION'));
      expect(teamIds(r), 0);
    }, skip: skip);
  });

  group('binary', () {
    late Directory app;

    setUp(() {
      app = Directory('${tmp.path}/Kusunga.app/Contents/MacOS')
        ..createSync(recursive: true);
      // A signed bundle names its team inside, as the provisioning profile
      // and the signature do.
      File(
        '${tmp.path}/Kusunga.app/Contents/embedded.provisionprofile',
      ).writeAsStringSync('TeamIdentifier $_appTeam');
      File('${app.path}/Kusunga').writeAsStringSync('clean binary');
    });

    test('a clean bundle passes and the Team ID in it appears 0 times', () {
      final r = run(['binary', '${tmp.path}/Kusunga.app']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(teamIds(r), 0);
    }, skip: skip);

    test('a bundle with the QA switch fails and the Team ID appears 0 '
        'times', () {
      File(
        '${app.path}/Kusunga',
      ).writeAsStringSync('x KusungaAcceptSyntheticKeys y');
      final r = run(['binary', '${tmp.path}/Kusunga.app']);
      expect(r.exitCode, 1);
      expect(teamIds(r), 0);
    }, skip: skip);
  });
}
