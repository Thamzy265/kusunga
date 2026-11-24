// M1.10a (tester): Flutter 3.50 moved Material and Cupertino out of the SDK
// (ADR 0008). The old `package:flutter/material.dart` still compiles but is
// deprecated and is a different library from `material_ui`, so one file on
// the old import and another on the new one is a mix the analyzer accepts.
// Every Dart file we own (lib, test, tool, and any other folder) uses
// material_ui only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> ownDartFiles() sync* {
  for (final dir in ['lib', 'test', 'tool', 'integration_test']) {
    if (!Directory(dir).existsSync()) continue;
    for (final e in Directory(dir).listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) yield e;
    }
  }
}

void main() {
  flutterErrorLock();
  test('no file imports the deprecated SDK Material or Cupertino library, '
      'or reaches into their old src folders', () {
    final bad = RegExp(
      r'''(import|export)\s+['"]package:flutter/(material|cupertino)\.dart['"]'''
      r'''|package:flutter/src/(material|cupertino)/''',
    );
    final hits = [
      for (final f in ownDartFiles())
        if (bad.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(hits, isEmpty);
  });

  test('cupertino_ui is not imported directly: it is not a declared '
      'dependency, only material_ui is', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains(RegExp(r'^  material_ui: ', multiLine: true)));
    final direct = [
      for (final f in ownDartFiles())
        if (f.readAsStringSync().contains(
          RegExp(r"import\s+'package:cupertino_ui/"),
        ))
          f.path,
    ];
    expect(direct, isEmpty);
    expect(pubspec, isNot(contains('cupertino_ui')));
  });

  test('the scan reads the real tree: it finds the material_ui import', () {
    final withNew = ownDartFiles()
        .where(
          (f) => f.readAsStringSync().contains(
            'package:material_ui/material_ui.dart',
          ),
        )
        .length;
    expect(withNew, greaterThan(100));
  });
}

// Flutter 3.50's ChangeNotifier (package:listen) throws a StateError on use
// after dispose, where 3.44.6 threw a FlutterError (two close_service tests
// changed for it). The app must not depend on either type: no `FlutterError`
// is caught or named in lib/.
void flutterErrorLock() {
  test('lib/ never names FlutterError (no catch depends on the dispose '
      'error type)', () {
    final hits = [
      for (final e in Directory('lib').listSync(recursive: true))
        if (e is File &&
            e.path.endsWith('.dart') &&
            e.readAsStringSync().contains('FlutterError'))
          e.path,
    ];
    expect(hits, isEmpty);
  });
}
