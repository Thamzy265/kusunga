// M1.10c tester: ADR 0009 says only the two port files touch the native
// window and tray packages, and only through the native API. Nothing else
// enforced it: a screen that imported window_manager would work and would
// call the real plugin in its tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_text.dart';

// Built in pieces so this file does not match its own search.
final _pkgs = ['window_manager', 'tray_manager', 'nativeapi', 'cnativeapi'];
final _legacy =
    'legacy'
    '.dart';

List<File> _dartFiles(String dir) => [
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

String _norm(String path) => path.replaceAll('\\', '/');

void main() {
  const ports = {
    'lib/window/window_manager_port.dart',
    'lib/tray/tray_manager_port.dart',
  };

  /// Files that import (or export, or part-of) one of the native packages.
  Map<String, List<String>> importers() {
    final found = <String, List<String>>{};
    final re = RegExp(
      '''^\\s*(?:import|export)\\s+['"]package:(${_pkgs.join('|')})(?:_flutter)?/''',
      multiLine: true,
    );
    for (final f in [..._dartFiles('lib'), ..._dartFiles('test')]) {
      for (final m in re.allMatches(readSource(f.path))) {
        found.putIfAbsent(_norm(f.path), () => []).add(m.group(1)!);
      }
    }
    return found;
  }

  test('only the two port files import window_manager, tray_manager, '
      'nativeapi or cnativeapi, and no test does', () {
    expect(importers().keys.toSet(), ports);
  });

  test('the window port imports only window_manager and the tray port '
      'only tray_manager', () {
    final by = importers();
    expect(by['lib/window/window_manager_port.dart'], ['window_manager']);
    expect(by['lib/tray/tray_manager_port.dart'], ['tray_manager']);
  });

  test('nothing imports the deprecated bridge, and nothing in lib/ or '
      'test/ silences the analyzer around these packages', () {
    for (final f in [..._dartFiles('lib'), ..._dartFiles('test')]) {
      final text = readSource(f.path);
      expect(text, isNot(contains(_legacy)), reason: f.path);
      if (ports.contains(_norm(f.path))) {
        expect(text, isNot(contains('// ignore')), reason: f.path);
        expect(text, isNot(contains('ignore_for_file')), reason: f.path);
        expect(text, isNot(contains('deprecated_member_use')), reason: f.path);
      }
    }
  });

  test('the packages are direct dependencies and only these four '
      'native-window packages are named in pubspec.yaml', () {
    final pubspec = readSource('pubspec.yaml');
    expect(pubspec, contains('window_manager:'));
    expect(pubspec, contains('tray_manager:'));
    // The native core comes in through them: a direct nativeapi dependency
    // would let any file import it without a pubspec change to notice.
    expect(pubspec, isNot(contains('\n  nativeapi:')));
    expect(pubspec, isNot(contains('\n  nativeapi_flutter:')));
    expect(pubspec, isNot(contains('\n  cnativeapi:')));
  });
}
