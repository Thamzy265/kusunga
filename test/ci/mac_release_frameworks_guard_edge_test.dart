import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.10c tester: edge cases of `tool/mac_release_guards.sh frameworks` beyond
/// the developer's fixtures: names with spaces, the real framework layout
/// (Versions/A and a Versions/Current link), several faults at once, and the
/// rule that no Team ID is ever printed, in any failure. A fake `codesign`
/// first on the PATH reads the "signature" from marker files, so nothing is
/// signed and no real identity or Team ID is used.
const script = 'tool/mac_release_guards.sh';

// Like the developer's fake, but the marker is looked for next to the bundle's
// Versions/Current too, as a real signature is on the bundle.
const _fakeCodesign = r'''#!/usr/bin/env bash
target="${@: -1}"
case "$1" in
  --verify)
    [ -e "$target/.fake_invalid" ] && { echo "$target: invalid signature" >&2; exit 1; }
    [ -e "$target/.fake_team" ] || { echo "$target: code object is not signed at all" >&2; exit 1; }
    exit 0 ;;
  -dv)
    [ -e "$target/.fake_team" ] || { echo "$target: code object is not signed at all" >&2; exit 1; }
    echo "Executable=$target" >&2
    echo "TeamIdentifier=$(cat "$target/.fake_team")" >&2
    exit 0 ;;
esac
exit 3
''';

// Sentinels no message of the script could contain by chance.
const _appTeam = 'ZZAPPTEAM1';
const _otherTeam = 'ZZOTHERTM2';

void main() {
  late Directory tmp;
  late Directory bin;
  late Directory appDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('macfw edge');
    bin = Directory('${tmp.path}/bin')..createSync();
    final fake = File('${bin.path}/codesign')..writeAsStringSync(_fakeCodesign);
    Process.runSync('chmod', ['+x', fake.path]);
    appDir = Directory('${tmp.path}/Kusunga.app')..createSync();
    File('${appDir.path}/.fake_team').writeAsStringSync(_appTeam);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A framework with the layout the real ones have: Versions/A holds the
  /// code, Versions/Current and the top-level names are links, and the
  /// signature is on the bundle root.
  void framework(
    String name, {
    String? team = _appTeam,
    bool invalid = false,
    bool realLayout = true,
  }) {
    final dir = Directory('${appDir.path}/Contents/Frameworks/$name.framework');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    if (realLayout) {
      Directory('${dir.path}/Versions/A').createSync(recursive: true);
      Link('${dir.path}/Versions/Current').createSync('A');
      Link('${dir.path}/$name').createSync('Versions/Current/$name');
    }
    if (team != null) File('${dir.path}/.fake_team').writeAsStringSync(team);
    if (invalid) File('${dir.path}/.fake_invalid').writeAsStringSync('');
  }

  void good() {
    framework('sqlite3mc');
    framework('cnativeapi');
    framework('App');
  }

  ProcessResult run([List<String>? args]) => runBash(
    script,
    args ?? ['frameworks', appDir.path],
    environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
  );

  String all(ProcessResult r) => '${r.stdout}${r.stderr}';

  final skip = skipOnWindows('codesign and the Mac release run on macOS only');

  test('passes on the real framework layout (Versions/Current link) and in '
      'an app path with a space', () {
    good();
    final r = run();
    expect(r.exitCode, 0, reason: all(r));
  }, skip: skip);

  test('a framework name with spaces is checked, and named when it fails', () {
    good();
    framework('My Plugin', team: _otherTeam);
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('My Plugin.framework'));
  }, skip: skip);

  test('a framework name with spaces that is signed right passes', () {
    good();
    framework('My Plugin');
    final r = run();
    expect(r.exitCode, 0, reason: all(r));
  }, skip: skip);

  test('an extra unsigned framework fails and is named', () {
    good();
    framework('extra', team: null);
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('extra.framework'));
  }, skip: skip);

  test('an extra ad-hoc framework (team "not set") fails and is named', () {
    good();
    framework('extra', team: 'not set');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('extra.framework'));
  }, skip: skip);

  test('every fault is reported in one run, not only the first', () {
    framework('cnativeapi', team: _otherTeam);
    framework('extra', team: null);
    // sqlite3mc is missing.
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('sqlite3mc.framework'));
    expect(r.stderr, contains('cnativeapi.framework'));
    expect(r.stderr, contains('extra.framework'));
  }, skip: skip);

  test('an empty Frameworks folder fails and names both required ones', () {
    Directory('${appDir.path}/Contents/Frameworks').createSync(recursive: true);
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('sqlite3mc.framework'));
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('a required name that is a plain file, not a framework folder, '
      'counts as missing', () {
    framework('sqlite3mc');
    framework('App');
    File(
      '${appDir.path}/Contents/Frameworks/cnativeapi.framework',
    ).writeAsStringSync('not a bundle');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('a required framework with a similar name does not stand in for it', () {
    framework('sqlite3mc');
    framework('cnativeapi_flutter');
    framework('App');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('the Team ID of the app and of a framework is never printed, in any '
      'failure, on stdout or stderr', () {
    final faults = <String, void Function()>{
      'other team': () => framework('cnativeapi', team: _otherTeam),
      'unsigned': () => framework('cnativeapi', team: null),
      'ad-hoc': () => framework('cnativeapi', team: 'not set'),
      'invalid': () => framework('cnativeapi', invalid: true),
      'missing': () => Directory(
        '${appDir.path}/Contents/Frameworks/cnativeapi.framework',
      ).deleteSync(recursive: true),
      'extra other team': () => framework('extra', team: _otherTeam),
    };
    for (final MapEntry(key: name, value: fault) in faults.entries) {
      final contents = Directory('${appDir.path}/Contents');
      if (contents.existsSync()) contents.deleteSync(recursive: true);
      good();
      fault();
      final r = run();
      expect(r.exitCode, 1, reason: name);
      expect(all(r), isNot(contains(_appTeam)), reason: name);
      expect(all(r), isNot(contains(_otherTeam)), reason: name);
    }
  }, skip: skip);

  test('the Team ID is not printed when the app itself is the fault '
      '(framework team differs, app is ad-hoc or unsigned)', () {
    good();
    File('${appDir.path}/.fake_team').writeAsStringSync('not set');
    var r = run();
    expect(r.exitCode, 1);
    expect(all(r), isNot(contains(_appTeam)));
    File('${appDir.path}/.fake_team').deleteSync();
    r = run();
    expect(r.exitCode, 1);
    expect(all(r), isNot(contains(_appTeam)));
  }, skip: skip);

  test('a failure prints nothing on stdout, so "ok" can never be read '
      'from a failed run', () {
    good();
    framework('cnativeapi', team: _otherTeam);
    final r = run();
    expect(r.exitCode, 1);
    expect('${r.stdout}', isNot(contains('ok')));
  }, skip: skip);

  test('exit 2 for an empty path, an unknown mode, and extra arguments', () {
    good();
    expect(run(['frameworks', '']).exitCode, 2);
    expect(run(['framework', appDir.path]).exitCode, 2);
    expect(run(['frameworks', appDir.path, 'extra']).exitCode, 2);
    expect(run(['frameworks']).exitCode, 2);
  }, skip: skip);

  test('exit 2 when the path is a file, not an app folder', () {
    final f = File('${tmp.path}/file.app')..writeAsStringSync('x');
    expect(run(['frameworks', f.path]).exitCode, 2);
  }, skip: skip);

  test('the older binary and xcconfig modes still exist and still fail '
      'closed on a missing path', () {
    expect(run(['binary', '${tmp.path}/nope']).exitCode, 2);
    expect(run(['xcconfig', '${tmp.path}/nope']).exitCode, 2);
  }, skip: skip);

  test('the frameworks guard has no way to print a Team ID: the script '
      'never echoes the output of codesign', () {
    final text = File(script).readAsStringSync();
    // team_of reads codesign's text into a variable and prints one field only
    // for comparison; no echo/printf of that field or of the raw output.
    expect(text, isNot(contains('echo "\$app_team')));
    expect(text, isNot(contains('echo "\$team')));
    expect(text, isNot(contains(r'echo "$out"')));
    expect(text, isNot(contains(r'cat <<<')));
  }, skip: skip);
}
