import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.10c reviewer F4: `tool/mac_release_guards.sh frameworks` must check the
/// same things whatever shell options the caller exports. With
/// `SHELLOPTS=noglob` in the environment, bash starts with globbing off, and
/// the framework loop used to check nothing and print "ok". The guard also
/// verifies the app's own signature and everything nested in it (loose
/// .dylib files that are not in a framework), and it checks the two required
/// frameworks by name, failing when fewer than 2 were checked. A fake
/// `codesign` first on the PATH reads the "signature" from marker files and
/// logs every call, so nothing is signed and no real identity or Team ID is
/// used.
const script = 'tool/mac_release_guards.sh';

// `.fake_team` holds the Team ID (no file: not signed at all), `.fake_invalid`
// makes `--verify` fail, and with `--deep` a loose .dylib in
// Contents/Frameworks fails unless it holds FAKE_SIGNED, as an unsigned
// nested binary fails the real check. It is a bash script, so an exported
// noglob reaches it too: it turns globbing back on, as the real tool is not a
// script.
const _fakeCodesign = r'''#!/usr/bin/env bash
set +f
echo "$*" >> "$FAKE_CODESIGN_LOG"
target="${@: -1}"
case "$1" in
  --verify)
    [ -e "$target/.fake_invalid" ] && { echo "$target: invalid signature" >&2; exit 1; }
    [ -e "$target/.fake_team" ] || { echo "$target: code object is not signed at all" >&2; exit 1; }
    case " $* " in
      *" --deep "*)
        for f in "$target"/Contents/Frameworks/*.dylib; do
          [ -e "$f" ] || continue
          grep -q FAKE_SIGNED "$f" || { echo "$target: code object is not signed at all In subcomponent: $f" >&2; exit 1; }
        done ;;
    esac
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
const _appTeam = 'ZZAPPTEAM4';
const _otherTeam = 'ZZOTHERTM4';

void main() {
  late Directory tmp;
  late Directory bin;
  late Directory appDir;
  late File log;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('macfw noglob');
    bin = Directory('${tmp.path}/bin')..createSync();
    final fake = File('${bin.path}/codesign')..writeAsStringSync(_fakeCodesign);
    Process.runSync('chmod', ['+x', fake.path]);
    appDir = Directory('${tmp.path}/Kusunga.app')..createSync();
    File('${appDir.path}/.fake_team').writeAsStringSync(_appTeam);
    log = File('${tmp.path}/codesign.log')..writeAsStringSync('');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String frameworks() => '${appDir.path}/Contents/Frameworks';

  void framework(String name, {String? team = _appTeam}) {
    final dir = Directory('${frameworks()}/$name.framework')
      ..createSync(recursive: true);
    if (team != null) File('${dir.path}/.fake_team').writeAsStringSync(team);
  }

  void good() {
    framework('sqlite3mc');
    framework('cnativeapi');
    framework('App');
  }

  ProcessResult run({bool noglob = false}) => runBash(
    script,
    ['frameworks', appDir.path],
    environment: {
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'FAKE_CODESIGN_LOG': log.path,
      // What `set -f; export SHELLOPTS` in the caller's shell leaves behind.
      if (noglob)
        'SHELLOPTS': 'braceexpand:hashall:interactive-comments:noglob',
    },
  );

  String all(ProcessResult r) => '${r.stdout}${r.stderr}';
  List<String> calls() => log.readAsLinesSync();

  final skip = skipOnWindows('codesign and the Mac release run on macOS only');

  test('an exported noglob really starts bash with globbing off (so the '
      'tests below are not vacuous)', () {
    final probe = Process.runSync(
      findBash(),
      ['-c', r'echo /*'],
      environment: {
        'SHELLOPTS': 'braceexpand:hashall:interactive-comments:noglob',
      },
    );
    expect('${probe.stdout}'.trim(), '/*');
  }, skip: skip);

  group('with SHELLOPTS=noglob exported', () {
    test('a framework signed by another team still fails, and is named', () {
      good();
      framework('cnativeapi', team: _otherTeam);
      final r = run(noglob: true);
      expect(r.exitCode, 1, reason: all(r));
      expect(r.stderr, contains('cnativeapi.framework'));
      expect('${r.stdout}', isNot(contains('ok')));
    }, skip: skip);

    test('an extra framework that is not signed still fails, and is named', () {
      good();
      framework('extra', team: null);
      final r = run(noglob: true);
      expect(r.exitCode, 1, reason: all(r));
      expect(r.stderr, contains('extra.framework'));
    }, skip: skip);

    test('every framework is still verified, the two required ones too', () {
      good();
      final r = run(noglob: true);
      expect(r.exitCode, 0, reason: all(r));
      for (final name in ['sqlite3mc', 'cnativeapi', 'App']) {
        expect(
          calls(),
          contains('--verify --strict ${frameworks()}/$name.framework'),
          reason: name,
        );
      }
    }, skip: skip);

    test('a good app still passes, and nothing prints the Team ID', () {
      good();
      final r = run(noglob: true);
      expect(r.exitCode, 0, reason: all(r));
      expect(r.stdout, contains('ok'));
      expect(all(r), isNot(contains(_appTeam)));
    }, skip: skip);
  });

  test("the app's own signature is verified, with everything nested in it "
      '(--deep --strict)', () {
    good();
    final r = run();
    expect(r.exitCode, 0, reason: all(r));
    expect(calls(), contains('--verify --deep --strict ${appDir.path}'));
  }, skip: skip);

  test('an app whose own signature does not verify fails, even when every '
      'framework is signed right', () {
    good();
    File('${appDir.path}/.fake_invalid').writeAsStringSync('');
    final r = run();
    expect(r.exitCode, 1, reason: all(r));
    expect(r.stderr, contains('codesign --verify --deep --strict'));
    expect(all(r), isNot(contains(_appTeam)));
  }, skip: skip);

  test('a loose unsigned .dylib in Contents/Frameworks fails, also under '
      'noglob', () {
    good();
    File('${frameworks()}/libextra.dylib').writeAsStringSync('unsigned');
    for (final noglob in [false, true]) {
      final r = run(noglob: noglob);
      expect(r.exitCode, 1, reason: 'noglob: $noglob\n${all(r)}');
      expect(all(r), isNot(contains(_appTeam)), reason: 'noglob: $noglob');
    }
  }, skip: skip);

  test('a loose .dylib that is signed passes', () {
    good();
    File('${frameworks()}/libextra.dylib').writeAsStringSync('FAKE_SIGNED');
    final r = run();
    expect(r.exitCode, 0, reason: all(r));
  }, skip: skip);

  test('a missing required framework: named, and fewer than 2 required '
      'frameworks were checked, so it fails', () {
    framework('sqlite3mc');
    framework('App');
    final r = run();
    expect(r.exitCode, 1, reason: all(r));
    expect(r.stderr, contains('cnativeapi.framework is missing'));
    expect(r.stderr, contains('1 of the 2 required frameworks'));
  }, skip: skip);
}
