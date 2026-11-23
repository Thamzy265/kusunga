import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.9b regression tests for BUG-M1, M2, M3 and M5 in
/// tool/mac_release_guards.sh. Each was a defect found by the tester and is
/// fixed. Every one was a false pass (the guard said "ok" when it must not)
/// except BUG-M5, which was a wrong exit code.
final script = File('tool/mac_release_guards.sh').absolute.path;
const needle = 'KusungaAcceptSyntheticKeys';

ProcessResult guard(
  List<String> args, {
  Map<String, String>? env,
  String? cwd,
}) => runBash(script, args, environment: env, workingDirectory: cwd);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('macguard_bugs'));
  tearDown(() => tmp.deleteSync(recursive: true));

  int xc(String body) {
    final f = File('${tmp.path}/Local.xcconfig.example')
      ..writeAsStringSync(body);
    return guard(['xcconfig', f.path]).exitCode;
  }

  group('BUG-M1 binary guard in a UTF-8 locale', () {
    test('finds the marker next to bytes that are not valid UTF-8', () {
      // grep -a in a UTF-8 locale skips a line holding an invalid sequence,
      // so the marker next to one is missed and the release passes.
      for (final bytes in [
        [0xFF, ...needle.codeUnits],
        [...needle.codeUnits, 0xFF],
        [0x80, ...needle.codeUnits, 0xC3],
      ]) {
        final f = File('${tmp.path}/Kusunga')..writeAsBytesSync(bytes);
        final r = guard(['binary', f.path], env: {'LC_ALL': 'en_US.UTF-8'});
        expect(r.exitCode, 1, reason: '$bytes');
      }
    });

    test('also with LANG only (a plain terminal)', () {
      final f = File('${tmp.path}/Kusunga')
        ..writeAsBytesSync([0xFF, ...needle.codeUnits, 0xFF]);
      final r = guard(
        ['binary', f.path],
        env: {'LANG': 'en_US.UTF-8', 'LC_ALL': ''},
      );
      expect(r.exitCode, 1);
    });
  });

  group('BUG-M2 OTHER_SWIFT_FLAGS -D that the guard does not see', () {
    test('no space around =', () {
      expect(xc('OTHER_SWIFT_FLAGS=-DKUSUNGA_X\n'), 1);
      expect(xc('OTHER_SWIFT_FLAGS=\$(inherited) -DX\n'), 1);
    });

    test('quoted flags', () {
      expect(xc('OTHER_SWIFT_FLAGS = "-DX"\n'), 1);
      expect(xc('OTHER_SWIFT_FLAGS = "-D" "X"\n'), 1);
      expect(xc('OTHER_SWIFT_FLAGS = \$(inherited) "-D" X\n'), 1);
    });
  });

  group('BUG-M3 a guard that scanned nothing must not pass', () {
    test('an empty file is nothing to scan (2)', () {
      final f = File('${tmp.path}/Kusunga')..writeAsBytesSync([]);
      expect(guard(['binary', f.path]).exitCode, 2);
    });

    test('a bundle whose files are all empty is nothing to scan (2)', () {
      final dir = Directory('${tmp.path}/Kusunga.app/Contents/MacOS')
        ..createSync(recursive: true);
      File('${dir.path}/Kusunga').writeAsBytesSync([]);
      expect(guard(['binary', '${tmp.path}/Kusunga.app']).exitCode, 2);
    });
  });

  group('BUG-M5 exit code 1 means only "marker found"', () {
    test('a path starting with a dash exits 2, not 1', () {
      Directory('${tmp.path}/-dash.app').createSync();
      File('${tmp.path}/-dash.app/f').writeAsStringSync('clean');
      final r = guard(['binary', '-dash.app'], cwd: tmp.path);
      expect(r.exitCode, 2);
    });
  });
}
