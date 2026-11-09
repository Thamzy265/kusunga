// Repros for the tester's findings on M1.5 (see the hand-off). Each test
// states the behaviour the design needs and FAILS today. They are skipped in
// the normal run so the check stays green; run them with
//   KUSUNGA_REPRO=1 flutter test test/shortcuts/typed_shortcuts_findings_test.dart
// and delete the skip once the developer has fixed the finding.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_shortcut.dart';

import '../support/fakes.dart';

final _skip = Platform.environment.containsKey('KUSUNGA_REPRO')
    ? null
    : 'tester finding open: run with KUSUNGA_REPRO=1';

SnippetService _service() => SnippetService(
  store: MemorySnippetStore(),
  log: FakeLog(),
  editable: true,
  writeClipboard: (_) async => true,
);

void main() {
  // T1: D1 only stops a shortcut from being the START of another. The native
  // matcher fires the moment the buffer ENDS with any shortcut, so a shortcut
  // that sits inside another one (not at its start) fires first and the longer
  // one can never be typed. Native tests lock that behaviour:
  // testAShortcutInsideAnotherOneFiresBeforeTheLongerOneIsFinished (Swift) and
  // TestEdgeBounds (C++). The editor should refuse the second shortcut.
  test(
    'T1 a shortcut that contains another one in its middle is refused',
    () {
      final s = _service();
      s.save(name: 'Ma', content: 'x', type: SnippetType.other, shortcut: 'ma');
      // ";email" contains "ma": typing it fires "ma" at the letter a.
      expect(s.shortcutIssue(';email'), isNotNull);
      final r = s.save(
        name: 'Work email',
        content: 'will@example.com',
        type: SnippetType.email,
        shortcut: ';email',
      );
      expect(r.outcome, isNot(SnippetSave.saved));
    },
    skip: _skip,
  );

  test('T1b the same the other way round: adding an inner shortcut after the '
      'longer one exists', () {
    final s = _service();
    s.save(
      name: 'Work email',
      content: 'x',
      type: SnippetType.email,
      shortcut: ';email',
    );
    expect(s.shortcutIssue('ma'), isNotNull);
  }, skip: _skip);

  // T2: a lone surrogate passes the Dart check, but the encrypted file stores
  // U+FFFD, so what native gets is not what the user typed, and two different
  // lone-surrogate shortcuts collide in the unique index (a generic "save
  // failed" instead of a clash message).
  // Fixed: refused with the existing "can't have" error (spaces problem).
  test('T2 a lone surrogate is not a valid shortcut', () {
    expect(checkShortcutText('\uD800a'), ShortcutProblem.spaces);
    expect(checkShortcutText('a\uDC00'), ShortcutProblem.spaces);
    // A whole surrogate pair (an emoji) is still fine.
    expect(checkShortcutText(';\u{1F600}'), isNull);
  });
}
