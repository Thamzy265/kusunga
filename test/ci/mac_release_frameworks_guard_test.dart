import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.10c: the release guard for the native-asset frameworks
/// (`tool/mac_release_guards.sh frameworks`). The app now ships cnativeapi
/// (window_manager and tray_manager, ADR 0009) next to sqlite3mc, and both must
/// be signed by the same team as the app. Tested on fixtures with a fake
/// `codesign` first on the PATH: nothing is signed here, and no real identity
/// or Team ID is used.
const script = 'tool/mac_release_guards.sh';

// The fake reads the signature from marker files in the bundle it is asked
// about: `.fake_team` holds the Team ID (no file: not signed at all), and
// `.fake_invalid` makes `--verify` fail. Like the real tool, it prints the
// details on stderr.
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
    echo "Identifier=fake" >&2
    echo "TeamIdentifier=$(cat "$target/.fake_team")" >&2
    exit 0 ;;
esac
echo "fake codesign: unexpected arguments $*" >&2
exit 3
''';

void main() {
  late Directory tmp;
  late Directory bin;
  late Directory appDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('macfw');
    bin = Directory('${tmp.path}/bin')..createSync();
    final fake = File('${bin.path}/codesign')..writeAsStringSync(_fakeCodesign);
    Process.runSync('chmod', ['+x', fake.path]);
    appDir = Directory('${tmp.path}/Kusunga.app')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Signs (in the fake's terms) [path] inside the app with [team]; null
  /// leaves it unsigned.
  void bundle(String path, {String? team, bool invalid = false}) {
    final dir = Directory('${appDir.path}/$path')..createSync(recursive: true);
    if (team != null) File('${dir.path}/.fake_team').writeAsStringSync(team);
    if (invalid) File('${dir.path}/.fake_invalid').writeAsStringSync('');
  }

  void signedApp({String team = 'TEAM1', List<String>? frameworks}) {
    File('${appDir.path}/.fake_team').writeAsStringSync(team);
    for (final f in frameworks ?? ['sqlite3mc', 'cnativeapi', 'App']) {
      bundle('Contents/Frameworks/$f.framework', team: team);
    }
  }

  ProcessResult run([String? path]) => runBash(
    script,
    ['frameworks', path ?? appDir.path],
    environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
  );

  final skip = skipOnWindows('codesign and the Mac release run on macOS only');

  test('passes when sqlite3mc, cnativeapi and every framework are signed by '
      "the app's team", () {
    signedApp();
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('ok'));
  }, skip: skip);

  test('fails when cnativeapi is signed by another team', () {
    signedApp();
    bundle('Contents/Frameworks/cnativeapi.framework', team: 'OTHER');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('fails when cnativeapi is ad-hoc signed (no team)', () {
    signedApp();
    bundle('Contents/Frameworks/cnativeapi.framework', team: 'not set');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('fails when sqlite3mc is not signed at all', () {
    signedApp(frameworks: ['cnativeapi', 'App']);
    bundle('Contents/Frameworks/sqlite3mc.framework');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('sqlite3mc.framework'));
  }, skip: skip);

  test('fails when a framework does not pass codesign --verify', () {
    signedApp();
    bundle(
      'Contents/Frameworks/cnativeapi.framework',
      team: 'TEAM1',
      invalid: true,
    );
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('fails when any other framework is signed by another team', () {
    signedApp();
    bundle('Contents/Frameworks/objective_c.framework', team: 'OTHER');
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('objective_c.framework'));
  }, skip: skip);

  test('fails when cnativeapi is missing', () {
    signedApp(frameworks: ['sqlite3mc', 'App']);
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('cnativeapi.framework'));
  }, skip: skip);

  test('fails when sqlite3mc is missing', () {
    signedApp(frameworks: ['cnativeapi', 'App']);
    final r = run();
    expect(r.exitCode, 1);
    expect(r.stderr, contains('sqlite3mc.framework'));
  }, skip: skip);

  test('fails when the app itself has no team (ad-hoc build)', () {
    signedApp(team: 'not set');
    final r = run();
    expect(r.exitCode, 1);
  }, skip: skip);

  test('fails when the app is not signed at all', () {
    signedApp();
    File('${appDir.path}/.fake_team').deleteSync();
    final r = run();
    expect(r.exitCode, 1);
  }, skip: skip);

  test('never prints the Team ID', () {
    signedApp(team: 'SECRETTEAM');
    bundle('Contents/Frameworks/cnativeapi.framework', team: 'OTHERTEAM');
    final failed = run();
    expect(failed.exitCode, 1);
    expect('${failed.stdout}${failed.stderr}', isNot(contains('SECRETTEAM')));
    expect('${failed.stdout}${failed.stderr}', isNot(contains('OTHERTEAM')));
    File(
      '${appDir.path}/Contents/Frameworks/cnativeapi.framework/.fake_team',
    ).writeAsStringSync('SECRETTEAM');
    final ok = run();
    expect(ok.exitCode, 0, reason: '${ok.stderr}');
    expect('${ok.stdout}${ok.stderr}', isNot(contains('SECRETTEAM')));
  }, skip: skip);

  test('exit 2 when the path does not exist, so a typo cannot pass', () {
    expect(run('${tmp.path}/missing.app').exitCode, 2);
  }, skip: skip);

  test('exit 2 when the app has no Frameworks folder', () {
    File('${appDir.path}/.fake_team').writeAsStringSync('TEAM1');
    expect(run().exitCode, 2);
  }, skip: skip);

  test('refuses a path that starts with a dash', () {
    expect(run('-x.app').exitCode, 2);
  }, skip: skip);

  test('the usage line names the frameworks mode', () {
    final r = runBash(script, const []);
    expect(r.exitCode, 2);
    expect(r.stderr, contains('frameworks <app>'));
  }, skip: skip);
}
