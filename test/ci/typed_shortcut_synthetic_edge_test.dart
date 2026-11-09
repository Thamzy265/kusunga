// Tester round 7: the Debug-only synthetic-keys switch (PM decision
// 2026-11-09). The Swift side of the argument gates is tested in
// TypedShortcutCoreTests.swift (SyntheticKeysSwitchEdgeTests). Here:
//  - the invariant that links it to the Dart data profile: whenever the
//    switch is on, the app is NOT on the real data;
//  - the build settings keep DEBUG out of Release and Profile, and the two
//    test scripts compile with and without it;
//  - repros (skipped) for two ways past the "inside #if DEBUG" source guard.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/data_profile.dart';

import '../support/swift_conditional.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('the switch never runs on the real data', () {
    // Argument lists on which SyntheticKeysSwitch.isOn is true (each one is
    // also asserted true in the Swift tests). The Dart side must read a
    // profile folder or refuse to open anything: never the real folder.
    const swiftOn = <List<String>>[
      ['/K', '-KusungaDataProfile', 'qa', '-KusungaAcceptSyntheticKeys', 'YES'],
      [
        '/K',
        '-KusungaAcceptSyntheticKeys',
        'YES',
        '-KusungaDataProfile',
        'dev',
      ],
      ['-KusungaDataProfile', 'qa', '-KusungaAcceptSyntheticKeys', 'YES'],
      [
        '/K',
        '-KusungaDataProfile',
        'qa',
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '-KusungaAcceptSyntheticKeys',
        'YES',
      ],
      // Extra look-alike switches that Swift ignores but Dart rejects.
      [
        '/K',
        '-KusungaDataProfile',
        'qa',
        '-KusungaAcceptSyntheticKeys',
        'YES',
        '-KusungaDataProfile=real',
      ],
      [
        '/K',
        '-KusungaDataProfile',
        'qa',
        '-KusungaAcceptSyntheticKeys',
        'YES',
        '-kusungadataprofile',
        'real',
      ],
      [
        '/K',
        '-KusungaDataProfile',
        'qa',
        '-KusungaAcceptSyntheticKeys',
        'YES',
        '−KusungaDataProfile',
        'real',
      ],
    ];

    test('every list that turns the switch on is a profile or a refusal in '
        'Dart, never the real folder', () {
      for (final args in swiftOn) {
        final p = dataProfileFrom(args, debug: true);
        expect(p, isNot(isA<NoDataProfile>()), reason: '$args');
      }
    });

    test('lists that Swift turns off may still be anything in Dart; the '
        'switch alone never selects a profile', () {
      for (final args in <List<String>>[
        ['/K', '-KusungaAcceptSyntheticKeys', 'YES'],
        ['/K', '-KusungaAcceptSyntheticKeys=YES', '-KusungaDataProfile', 'qa'],
      ]) {
        final p = dataProfileFrom(args, debug: true);
        if (args.contains('-KusungaDataProfile')) {
          expect(p, isA<ActiveDataProfile>());
        } else {
          expect(
            p,
            isA<NoDataProfile>(),
            reason: 'the real folder: switch off',
          );
        }
      }
    });

    test('a Release or Profile Dart build ignores the profile, so it must not '
        'be paired with a switch that is on: the switch is compiled only into '
        'Debug', () {
      expect(
        dataProfileFrom([
          '/K',
          '-KusungaDataProfile',
          'qa',
          '-KusungaAcceptSyntheticKeys',
          'YES',
        ], debug: false),
        isA<NoDataProfile>(),
      );
    });
  });

  group(
    'DEBUG exists only in the Debug build and in the debug test script',
    () {
      test('only the Debug project configuration defines DEBUG', () {
        final lines = _read(
          'macos/Runner.xcodeproj/project.pbxproj',
        ).split('\n');
        var found = 0;
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('SWIFT_ACTIVE_COMPILATION_CONDITIONS') &&
              !lines[i].contains('OTHER_SWIFT_FLAGS')) {
            continue;
          }
          found++;
          // The configuration's name comes at the end of its block.
          var j = i;
          while (j < lines.length &&
              !RegExp(r'^\s*name = ').hasMatch(lines[j])) {
            j++;
          }
          final name = RegExp(r'name = (\w+);').firstMatch(lines[j])!.group(1);
          if (lines[i].contains('DEBUG')) {
            expect(name, 'Debug', reason: 'line ${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(found, greaterThanOrEqualTo(1));
        // No xcconfig adds it elsewhere.
        for (final f
            in Directory('macos/Runner/Configs')
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.xcconfig'))) {
          expect(
            _read(f.path),
            isNot(
              matches(
                RegExp(r'SWIFT_ACTIVE_COMPILATION_CONDITIONS|-D\s*DEBUG'),
              ),
            ),
            reason: f.path,
          );
        }
      });

      test(
        'the debug script compiles with -D DEBUG, the release script without, '
        'and both compile the same sources',
        () {
          final debug = _read('tool/test_mac_shortcuts.sh');
          final release = _read('tool/test_mac_shortcuts_release.sh');
          expect(debug, contains('-D DEBUG'));
          final code = release
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('#'))
              .join('\n');
          expect(code, isNot(contains('DEBUG')));
          for (final src in [
            'macos/Runner/TypedShortcutCore.swift',
            'macos/RunnerTests/TypedShortcutCoreTests.swift',
          ]) {
            expect(debug, contains(src));
            expect(release, contains(src));
          }
        },
      );
    },
  );

  // The guards classify lines with the shared helper
  // (test/support/swift_conditional.dart), so these tests check exactly what
  // the guards use.
  bool inDebug(String src, String needle) =>
      swiftDebugLines(src).firstWhere((l) => l.$1.contains(needle)).$2;

  group('the guard classifies what the compiler would', () {
    test('plain cases are right (regression lock for the guard)', () {
      expect(inDebug('#if DEBUG\nLEAK\n#endif', 'LEAK'), isTrue);
      expect(inDebug('#if DEBUG\n#else\nLEAK\n#endif', 'LEAK'), isFalse);
      expect(inDebug('#if !DEBUG\nLEAK\n#endif', 'LEAK'), isFalse);
      expect(
        inDebug('#if os(iOS)\n#elseif DEBUG\nLEAK\n#endif', 'LEAK'),
        isFalse,
      );
      expect(
        inDebug('#if os(iOS)\n#else\n#if DEBUG\n#endif\nLEAK\n#endif', 'LEAK'),
        isFalse,
      );
      expect(
        inDebug('#if DEBUG\n#if os(macOS)\n#endif\nLEAK\n#endif', 'LEAK'),
        isTrue,
      );
    });

    final repro = Platform.environment.containsKey('KUSUNGA_REPRO')
        ? null
        : 'tester finding open: run with KUSUNGA_REPRO=1';

    // G1: `#if DEBUG || true` (or `|| anything`) is true in Release too, but
    // the guard reads it as a DEBUG block.
    test(
      'G1 a compound condition that is also true in Release is not DEBUG',
      () {
        expect(inDebug('#if DEBUG || true\nLEAK\n#endif', 'LEAK'), isFalse);
        expect(
          inDebug('#if DEBUG || os(macOS)\nLEAK\n#endif', 'LEAK'),
          isFalse,
        );
        expect(inDebug('#if DEBUG||true\nLEAK\n#endif', 'LEAK'), isFalse);
        expect(inDebug('#if DEBUG && true\nLEAK\n#endif', 'LEAK'), isFalse);
        expect(inDebug('#if (DEBUG)\nLEAK\n#endif', 'LEAK'), isFalse);
        // A bare #if DEBUG, with spaces or a line comment after it, counts.
        expect(inDebug('#if DEBUG  \nLEAK\n#endif', 'LEAK'), isTrue);
        expect(inDebug('  #if DEBUG\t\nLEAK\n#endif', 'LEAK'), isTrue);
        expect(inDebug('#if DEBUG // QA only\nLEAK\n#endif', 'LEAK'), isTrue);
        expect(inDebug('#if DEBUG//x\nLEAK\n#endif', 'LEAK'), isTrue);
      },
    );

    // G2: a block comment that contains a line starting with `#if DEBUG`
    // makes the guard think the code after it is inside a DEBUG block.
    test('G2 an #if DEBUG line inside a block comment is not a block', () {
      expect(inDebug('/*\n#if DEBUG\n*/\nLEAK', 'LEAK'), isFalse);
    }, skip: repro);
  });
}
