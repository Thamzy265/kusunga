import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The test data profile (`-KusungaDataProfile <name>`) exists in Debug
/// builds only, like `-KusungaForcePost` (6e24bed): the Mac side passes it
/// on only inside `#if DEBUG`, and Dart reads it only when `kDebugMode`, so a
/// Release build (Mac or Windows) never uses another data folder.
void main() {
  String read(String path) => File(path).readAsStringSync();
  String stripComments(String code) =>
      code.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  const key = 'KusungaDataProfile';

  test('Dart reads it only when kDebugMode', () {
    final src = stripComments(read('lib/history/data_profile.dart'));
    // Spaces and commas removed, so formatting does not matter.
    expect(
      src.replaceAll(RegExp(r'[\s,]'), ''),
      contains(
        'DataProfiledataProfileFrom(List<String>args{booldebug=kDebugMode})'
        '{if(!debug)returnconstNoDataProfile();',
      ),
    );
  });

  test('main() never overrides the debug check', () {
    final main = stripComments(read('lib/main.dart'));
    expect(main, contains('dataProfileFrom(args)'));
    // The "switch wasn't recognised" banner (QA-M14-6) follows the parsed
    // profile, so a Release build (never a RejectedDataProfile) never
    // shows it.
    expect(
      main.replaceAll(RegExp(r'\s'), ''),
      contains('dataProfileRejected:profileisRejectedDataProfile'),
    );
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final text = stripComments(e.readAsStringSync());
      expect(
        RegExp(r'dataProfileFrom\([^)]*debug\s*:').hasMatch(text),
        isFalse,
        reason: e.path,
      );
    }
  });

  test('the Mac side passes the launch arguments on only inside #if DEBUG', () {
    // Dart decides (exact form, name, mistyped forms): the Mac side passes
    // the command line on, in Debug only, as the Windows runner does.
    final swift = stripComments(read('macos/Runner/MainFlutterWindow.swift'));
    final ifDebug = swift.indexOf('#if DEBUG');
    final endIf = swift.indexOf('#endif', ifDebug);
    expect(ifDebug, isNonNegative);
    expect(endIf, greaterThan(ifDebug));
    final inside = swift.substring(ifDebug, endIf);
    expect(
      inside,
      contains(
        'project.dartEntrypointArguments = Array(CommandLine.arguments'
        '.dropFirst())',
      ),
    );
    expect(inside, isNot(contains('#else')));
    final outside = swift.substring(0, ifDebug) + swift.substring(endIf);
    expect(outside, isNot(contains('dartEntrypointArguments')));
    expect(outside, isNot(contains('CommandLine')));
  });

  test('the key name appears nowhere else in the app sources', () {
    for (final e in [
      ...Directory('macos/Runner').listSync(recursive: true),
      ...Directory('lib').listSync(recursive: true),
      ...Directory('windows/runner').listSync(recursive: true),
    ]) {
      if (e is! File) continue;
      if (!RegExp(r'\.(swift|dart|cpp|h)$').hasMatch(e.path)) continue;
      final text = stripComments(e.readAsStringSync());
      final n = key.allMatches(text).length;
      if (e.path.endsWith('data_profile.dart')) {
        expect(n, greaterThan(0), reason: e.path);
      } else if (e.path.endsWith('TypedShortcutCore.swift')) {
        // QA's synthetic-keys switch (PM 2026-11-09) is on only with a test
        // profile, and is compiled into Debug builds only: the name may
        // appear there, inside #if DEBUG blocks and nowhere else.
        final outside = text.replaceAll(RegExp(r'#if DEBUG[\s\S]*?#endif'), '');
        expect(key.allMatches(outside).length, 0, reason: e.path);
      } else {
        expect(n, 0, reason: e.path);
      }
    }
  });

  test('nothing turns it on from the project, plist, entitlements or CI', () {
    final files = <String>[
      'macos/Runner/Info.plist',
      'macos/Runner/Release.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner.xcodeproj/project.pbxproj',
      '.github/workflows/check.yml',
      'tool/check.sh',
      'tool/check.ps1',
    ];
    for (final dir in [
      'macos/Runner.xcodeproj/xcshareddata',
      'macos/Runner.xcworkspace',
      '.vscode',
    ]) {
      if (Directory(dir).existsSync()) {
        files.addAll(
          Directory(
            dir,
          ).listSync(recursive: true).whereType<File>().map((f) => f.path),
        );
      }
    }
    for (final f in files) {
      if (File(f).existsSync()) {
        expect(read(f), isNot(contains(key)), reason: f);
      }
    }
  });
}
