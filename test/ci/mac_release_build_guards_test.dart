import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bash.dart';

/// M1.9b: the Mac release build settings and the release-binary guards
/// (tool/mac_release_guards.sh, called by the release script in M1.9e).
/// The guard logic is tested on fixtures; nothing is built or signed here.
const script = 'tool/mac_release_guards.sh';

String read(String path) => File(path).readAsStringSync();

ProcessResult run(List<String> args) => runBash(script, args);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('macguard'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory app(Map<String, List<int>> files) {
    final dir = Directory('${tmp.path}/Kusunga.app')..createSync();
    files.forEach((rel, bytes) {
      File('${dir.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    });
    return dir;
  }

  List<int> binary(String embedded) => [
    0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0, //
    ...embedded.codeUnits,
    0, 1, 2, 3,
  ];

  group('binary guard', () {
    test('passes a bundle without the synthetic-keys switch', () {
      final dir = app({
        'Contents/MacOS/Kusunga': binary('KusungaDataProfile'),
        'Contents/Frameworks/X.framework/X': binary('hello'),
      });
      expect(run(['binary', dir.path]).exitCode, 0);
    });

    test('fails when the main binary contains the switch', () {
      final dir = app({
        'Contents/MacOS/Kusunga': binary('-KusungaAcceptSyntheticKeys'),
      });
      final r = run(['binary', dir.path]);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('KusungaAcceptSyntheticKeys'));
    });

    test('fails when a framework contains the switch', () {
      final dir = app({
        'Contents/MacOS/Kusunga': binary('ok'),
        'Contents/Frameworks/X.framework/X': binary(
          'KusungaAcceptSyntheticKeys',
        ),
      });
      expect(run(['binary', dir.path]).exitCode, 1);
    });

    test('accepts a single file path too', () {
      final f = File('${tmp.path}/Kusunga')
        ..writeAsBytesSync(binary('KusungaAcceptSyntheticKeys'));
      expect(run(['binary', f.path]).exitCode, 1);
    });

    test('fails when the path does not exist, so a typo cannot pass', () {
      expect(run(['binary', '${tmp.path}/missing.app']).exitCode, 2);
    });

    test('fails when the bundle holds no files', () {
      final dir = Directory('${tmp.path}/Empty.app')..createSync();
      expect(run(['binary', dir.path]).exitCode, 2);
    });
  });

  group('xcconfig guard', () {
    int check(String body) {
      final f = File('${tmp.path}/Local.xcconfig.example')
        ..writeAsStringSync(body);
      return run(['xcconfig', f.path]).exitCode;
    }

    test('passes signing-only settings and comments mentioning the key', () {
      expect(
        check(
          '// SWIFT_ACTIVE_COMPILATION_CONDITIONS is not allowed here\n'
          'DEVELOPMENT_TEAM = YOURTEAMID\n'
          'CODE_SIGN_STYLE = Automatic\n',
        ),
        0,
      );
    });

    test('fails on SWIFT_ACTIVE_COMPILATION_CONDITIONS', () {
      expect(check('SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG\n'), 1);
      expect(
        check('  SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) X\n'),
        1,
      );
      expect(
        check('SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Release] = X\n'),
        1,
      );
    });

    test('fails on a -D flag in OTHER_SWIFT_FLAGS', () {
      expect(check('OTHER_SWIFT_FLAGS = \$(inherited) -D DEBUG\n'), 1);
      expect(check('OTHER_SWIFT_FLAGS = -DDEBUG\n'), 1);
    });

    test('fails when the file is missing', () {
      expect(run(['xcconfig', '${tmp.path}/nope']).exitCode, 2);
    });

    test('the real example file passes', () {
      expect(
        run([
          'xcconfig',
          'macos/Runner/Configs/Local.xcconfig.example',
        ]).exitCode,
        0,
      );
    });
  });

  group('build settings (AC3, AC8, AC9)', () {
    final release = read('macos/Runner/Configs/Release.xcconfig');
    bool sets(String text, String key, String value) => RegExp(
      '^\\s*$key\\s*=\\s*$value\\s*\$',
      multiLine: true,
    ).hasMatch(text);

    test('release and profile build for Apple silicon only (D3 A)', () {
      // The project-level Release and Profile configurations both use
      // Release.xcconfig as their base file.
      expect(sets(release, 'ARCHS', 'arm64'), isTrue);
      final pbx = read('macos/Runner.xcodeproj/project.pbxproj');
      expect(pbx, isNot(contains('x86_64')));
    });

    test('Hardened Runtime is on for release and profile', () {
      expect(sets(release, 'ENABLE_HARDENED_RUNTIME', 'YES'), isTrue);
    });

    test('no entitlement exception was added for Hardened Runtime', () {
      final plist = read('macos/Runner/Release.entitlements');
      for (final k in [
        'allow-unsigned-executable-memory',
        'allow-dyld-environment-variables',
        'disable-library-validation',
        'disable-executable-page-protection',
        'allow-jit',
      ]) {
        expect(plist, isNot(contains(k)), reason: k);
      }
    });

    test('the minimum macOS is stated in ADR 0003', () {
      expect(
        read('docs/adr/0003-mac-distribution-and-sandbox.md'),
        contains('macOS 12.0'),
      );
      expect(
        read('macos/Runner.xcodeproj/project.pbxproj'),
        contains('MACOSX_DEPLOYMENT_TARGET = 12.0;'),
      );
    });
  });
}
