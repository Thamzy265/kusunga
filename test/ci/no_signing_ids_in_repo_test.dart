import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A signing team id or certificate id is not secret in the way a password is,
/// but it identifies a person's Apple account, so it must not be committed
/// anywhere (code, docs, QA notes). The placeholder and a redacted form pass.
final _patterns = <String, RegExp>{
  'DEVELOPMENT_TEAM': RegExp(r'DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\b'),
  'TeamIdentifier': RegExp(r'TeamIdentifier[=\s:]+([A-Z0-9]{10})\b'),
  'certificate id': RegExp(
    r'Apple (?:Development|Distribution): [^()\n]*\(([A-Z0-9]{10})\)',
  ),
};

const _allowed = {'YOURTEAMID'};

/// What is wrong with [text], as "kind: id" lines.
List<String> findIds(String text) => [
  for (final e in _patterns.entries)
    for (final m in e.value.allMatches(text))
      if (!_allowed.contains(m.group(1))) '${e.key}: ${m.group(1)}',
];

void main() {
  group('the detector', () {
    final fake =
        'ABCDE'
        '12345';

    test('finds each form', () {
      expect(findIds('DEVELOPMENT_TEAM = $fake'), hasLength(1));
      expect(findIds('TeamIdentifier=$fake'), hasLength(1));
      expect(findIds('TeamIdentifier $fake,'), hasLength(1));
      expect(
        findIds('Authority=Apple Development: Some Name ($fake)'),
        hasLength(1),
      );
      expect(findIds('Apple Development: a@b.c ($fake) >'), hasLength(1));
    });

    test('lets the placeholder and the redacted form through', () {
      expect(findIds('DEVELOPMENT_TEAM = YOURTEAMID'), isEmpty);
      expect(findIds('TeamIdentifier=<local team, redacted>'), isEmpty);
      expect(findIds('TeamIdentifier=not set'), isEmpty);
      expect(
        findIds('Authority=Apple Development: <local account, redacted>'),
        isEmpty,
      );
    });
  });

  test('no tracked text file carries a team id or a certificate id', () {
    final files = (Process.runSync('git', ['ls-files']).stdout as String)
        .split('\n')
        .where((f) => f.isNotEmpty && File(f).existsSync());
    final problems = <String>[];
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      if (bytes.contains(0)) continue; // binary
      final text = utf8.decode(bytes, allowMalformed: true);
      for (final p in findIds(text)) {
        problems.add('$f: $p');
      }
    }
    expect(problems, isEmpty, reason: 'real signing ids in tracked files');
  });
}
