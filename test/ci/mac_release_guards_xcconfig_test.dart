import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.9b review round 3: regression tests for tool/mac_release_guards.sh.
/// R1: the xcconfig guard allow-lists the signing keys and rejects any other
///     key and any -D token (Xcode honours spellings a deny-list missed).
/// R2: an unreadable or very large file must not pass by accident.
final script = File('tool/mac_release_guards.sh').absolute.path;

ProcessResult guard(List<String> args) => runBash(script, args);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('macguard_xc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  int xc(String body) {
    final f = File('${tmp.path}/Local.xcconfig.example')
      ..writeAsStringSync(body);
    return guard(['xcconfig', f.path]).exitCode;
  }

  group('R1 xcconfig guard: spellings Xcode honours', () {
    test('(a) single-quoted -D flag', () {
      expect(xc("OTHER_SWIFT_FLAGS = \$(inherited) '-DDEBUG'\n"), 1);
    });

    test('(b) -D hidden behind another variable', () {
      expect(
        xc(
          'KUSUNGA_FLAGS = -DDEBUG\n'
          'OTHER_SWIFT_FLAGS = \$(inherited) \$(KUSUNGA_FLAGS)\n',
        ),
        1,
      );
    });

    test('(c) -D glued to \$(inherited)', () {
      expect(xc('OTHER_SWIFT_FLAGS = \$(inherited)-DDEBUG\n'), 1);
    });

    test('(d) CR-only line endings', () {
      expect(
        xc(
          'DEVELOPMENT_TEAM = X\rSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG\r',
        ),
        1,
      );
    });

    test('any key outside the signing allow-list fails', () {
      expect(xc('KUSUNGA_FLAGS = harmless\n'), 1);
      expect(xc('swift_active_compilation_conditions = X\n'), 1);
      expect(xc('OTHER_SWIFT_FLAGS = -Onone\n'), 1);
      expect(xc('#include "Other.xcconfig"\n'), 1);
      expect(xc('#include? "Local.xcconfig"\n'), 1);
      expect(xc('DEVELOPMENT_TEAM = X \\\nOTHER = Y\n'), 1);
    });

    test('a -D token in an allowed key fails, a word like My-Dev does not', () {
      expect(xc('CODE_SIGN_IDENTITY = -DX\n'), 1);
      expect(xc('PROVISIONING_PROFILE_SPECIFIER = My-Dev Profile\n'), 0);
    });

    test(
      'a -D in a trailing comment fails, a whole-line comment is skipped',
      () {
        expect(xc('DEVELOPMENT_TEAM = X // -DX\n'), 1);
        expect(
          xc('// OTHER_SWIFT_FLAGS = -DX\n  // -DX\nDEVELOPMENT_TEAM = X\n'),
          0,
        );
      },
    );

    test('the signing keys pass, with [sdk] and [config] conditions', () {
      expect(
        xc(
          'DEVELOPMENT_TEAM = YOURTEAMID\n'
          'CODE_SIGN_STYLE = Automatic\n'
          'CODE_SIGN_IDENTITY = Apple Development\n'
          'PROVISIONING_PROFILE_SPECIFIER = My Profile\n',
        ),
        0,
      );
      expect(xc('DEVELOPMENT_TEAM[sdk=macosx*] = X\n'), 0);
      expect(xc('CODE_SIGN_IDENTITY[config=Release][sdk=macosx*] = X\n'), 0);
      expect(xc('\tDEVELOPMENT_TEAM\t=\tX\r\n\r\n'), 0);
      expect(xc(''), 0);
    });

    test('the real Local.xcconfig.example passes', () {
      expect(
        guard([
          'xcconfig',
          'macos/Runner/Configs/Local.xcconfig.example',
        ]).exitCode,
        0,
      );
    });

    test('the build xcconfig files set no Swift compilation conditions', () {
      // The guard is for the signing example only (an allow-list); these build
      // files legitimately set other keys, so check them for the two ways to
      // switch DEBUG code on.
      for (final f in [
        'macos/Runner/Configs/Release.xcconfig',
        'macos/Runner/Configs/AppInfo.xcconfig',
        'macos/Runner/Configs/Warnings.xcconfig',
        'macos/Flutter/Flutter-Release.xcconfig',
      ]) {
        final live = File(f)
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(live, isNot(contains('SWIFT_ACTIVE_COMPILATION_CONDITIONS')));
        expect(live, isNot(matches(RegExp(r'(^|[^A-Za-z0-9_])-D'))), reason: f);
      }
    });
  });

  group('R2 xcconfig guard: errors and large files are not a pass', () {
    test(
      'an unreadable file exits 2, never "ok"',
      () {
        if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
          return;
        }
        final f = File('${tmp.path}/Local.xcconfig.example')
          ..writeAsStringSync('DEVELOPMENT_TEAM = X\n');
        Process.runSync('chmod', ['000', f.path]);
        addTearDown(() => Process.runSync('chmod', ['644', f.path]));
        final r = guard(['xcconfig', f.path]);
        expect(r.exitCode, 2);
        expect(r.stdout, isNot(contains('ok')));
      },
      skip: skipOnWindows(
        'chmod 000 does not make a file unreadable on Windows',
      ),
    );

    test('a large file with the setting first still exits 1', () {
      final filler = List.filled(
        25000,
        'DEVELOPMENT_TEAM = FILLERFILLERFILLER',
      );
      for (final first in [
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG',
        'OTHER_SWIFT_FLAGS = -DDEBUG',
      ]) {
        final body = '$first\n${filler.join('\n')}\n';
        expect(body.length, greaterThan(600 * 1024));
        expect(xc(body), 1, reason: first);
      }
    });

    test('a large clean file exits 0', () {
      final filler = List.filled(
        25000,
        'DEVELOPMENT_TEAM = FILLERFILLERFILLER',
      );
      expect(xc('DEVELOPMENT_TEAM = X\n${filler.join('\n')}\n'), 0);
    });
  });
}
