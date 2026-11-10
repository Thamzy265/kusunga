// M1.6 fix round 2 (reviewer R7): the clipboard watcher and typed shortcuts
// use one copy of the rule that turns a process into its app id
// (windows/runner/app_id.h). Neither bridge keeps its own.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  const bridges = [
    'windows/runner/clipboard_bridge.cpp',
    'windows/runner/typed_shortcut_bridge.cpp',
  ];

  for (final path in bridges) {
    test('$path includes app_id.h and defines no process lookup', () {
      final src = _code(path);
      expect(src, contains('#include "app_id.h"'));
      expect(src, isNot(contains('QueryFullProcessImageNameW')));
      expect(src, isNot(contains('ExeNameOfWindow')));
      expect(src, isNot(matches(RegExp(r'std::wstring ImagePathOf\('))));
      expect(src, isNot(matches(RegExp(r'std::string AppIdOf\('))));
    });
  }

  test('the policy harness runs the app id test', () {
    expect(
      File('tool/test_windows_policy.sh').readAsStringSync(),
      contains('app_id_test'),
    );
  });
}
