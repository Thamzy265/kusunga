// M1.8 tester: crafted import files (docs/design/your-data.md, "Import",
// "Trust boundaries and abuse cases"). Every file here is something a person
// or a program could put on disk; the rule is that the whole file is refused
// with an [ImportRejected], never another exception and never a half read.
//
// Tests marked with [_repro] are bug repros: they fail today and are skipped
// so the check command stays green. Run them with KUSUNGA_REPRO=1.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';

Map<String, Object?> _file({
  Object? snippets = const <Object?>[],
  Object? history,
  Object? settings,
  Object? apps,
  Object? version = 1,
  Object? format = exportFormatName,
}) => {
  'format': format,
  'version': version,
  'exported_at': '2026-11-12T09:30:00Z',
  'snippets': snippets,
  'history': ?history,
  'settings': ?settings,
  'ignored_apps': ?apps,
};

Map<String, Object?> _snip({
  Object? name = 'Phone',
  Object? content = '07700 900123',
  Object? type = 'phone',
  Object? shortcut,
  Object? position = 0,
}) => {
  'name': name,
  'content': content,
  'type': type,
  'shortcut': shortcut,
  'position': position,
};

Map<String, Object?> _clip({
  Object? content = 'hello',
  Object? kind = 'text',
  Object? created = '2026-11-01T10:00:00Z',
  Object? last = '2026-11-02T10:00:00Z',
}) => {
  'content': content,
  'kind': kind,
  'created_at': created,
  'last_copied_at': last,
};

ExportBundle _decode(Object? json) =>
    decodeImport(utf8.encode(jsonEncode(json)));

Matcher _rejected([ImportRejectReason? reason]) => throwsA(
  isA<ImportRejected>().having(
    (e) => e.reason,
    'reason',
    reason ?? isA<ImportRejectReason>(),
  ),
);

void main() {
  group('JSON edge cases: the whole file is refused, with an ImportRejected', () {
    final raw = <String, String>{
      'NaN': '{"format":"kusunga-export","version":1,"snippets":[],"x":NaN}',
      'Infinity':
          '{"format":"kusunga-export","version":1,"snippets":[],"x":Infinity}',
      '-Infinity':
          '{"format":"kusunga-export","version":1,"snippets":[],"x":-Infinity}',
      'a trailing comma':
          '{"format":"kusunga-export","version":1,"snippets":[],}',
      'single quotes': "{'format':'kusunga-export','version':1,'snippets':[]}",
      'a comment': '{"format":"kusunga-export",/*x*/"version":1,"snippets":[]}',
      'two documents':
          '{"format":"kusunga-export","version":1,"snippets":[]}{"a":1}',
      'an unescaped NUL inside a string':
          '{"format":"kusunga-export","version":1,"snippets":[],"x":"a\u0000b"}',
      'an unescaped line break inside a string':
          '{"format":"kusunga-export","version":1,"snippets":[],"x":"a\nb"}',
      'a lone top-level null': 'null',
      'a top-level list': '[]',
      'a top-level string': '"kusunga-export"',
      'a top-level number': '1',
      'whitespace only': '   \n\t ',
      'a BOM in the middle':
          '{"format":"kusunga-export",\u{FEFF}"version":1,"snippets":[]}',
      'snippets null':
          '{"format":"kusunga-export","version":1,"snippets":null}',
      'snippets missing': '{"format":"kusunga-export","version":1}',
      'a null in the snippet list':
          '{"format":"kusunga-export","version":1,"snippets":[null]}',
      'history that is an object':
          '{"format":"kusunga-export","version":1,"snippets":[],"history":{}}',
      'ignored apps that are a string':
          '{"format":"kusunga-export","version":1,"snippets":[],'
          '"ignored_apps":"x"}',
      'a number as the file format': '{"format":1,"version":1,"snippets":[]}',
      'the version as text':
          '{"format":"kusunga-export","version":"1","snippets":[]}',
      'the version as 1.5':
          '{"format":"kusunga-export","version":1.5,"snippets":[]}',
      'the version a huge number':
          '{"format":"kusunga-export","version":99999999999999999999999,'
          '"snippets":[]}',
      'the version 1e999':
          '{"format":"kusunga-export","version":1e999,"snippets":[]}',
      'exported_at that is not a time':
          '{"format":"kusunga-export","version":1,"exported_at":"soon",'
          '"snippets":[]}',
      'exported_at a number':
          '{"format":"kusunga-export","version":1,"exported_at":5,'
          '"snippets":[]}',
    };
    for (final MapEntry(:key, :value) in raw.entries) {
      test(
        key,
        () => expect(() => decodeImport(utf8.encode(value)), _rejected()),
      );
    }

    test('the right reason numbers are kept apart', () {
      expect(
        () => decodeImport(utf8.encode('{"a":NaN}')),
        _rejected(ImportRejectReason.notJson),
      );
      expect(
        () => decodeImport(utf8.encode(jsonEncode(_file(version: '1')))),
        _rejected(ImportRejectReason.wrongFormat),
      );
      expect(
        () => decodeImport(utf8.encode(jsonEncode(_file(version: 2)))),
        _rejected(ImportRejectReason.newerVersion),
      );
    });

    test('duplicate keys: the last one wins, and a bad last one refuses', () {
      // dart:convert keeps the last value of a repeated key. The point is
      // that the check runs on what is kept, so a good first value cannot
      // hide a bad last one.
      final good =
          '{"format":"kusunga-export","version":1,"snippets":[],"snippets":'
          '[{"name":"A","content":"c","type":"other"}]}';
      expect(decodeImport(utf8.encode(good)).snippets.single.name, 'A');
      final bad =
          '{"format":"kusunga-export","version":1,"snippets":[{"name":"A",'
          '"content":"c","type":"other"}],"snippets":[{"name":""}]}';
      expect(() => decodeImport(utf8.encode(bad)), _rejected());
      final formatTwice =
          '{"format":"kusunga-export","format":"other","version":1,'
          '"snippets":[]}';
      expect(() => decodeImport(utf8.encode(formatTwice)), _rejected());
    });

    test('a UTF-8 BOM and then the file is fine', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(jsonEncode(_file()))];
      expect(decodeImport(bytes).snippets, isEmpty);
    });

    test('invalid UTF-8 is refused as such: overlong, a CESU-8 surrogate, '
        'a truncated sequence', () {
      const head = '{"format":"kusunga-export","version":1,"snippets":[],"x":"';
      const tail = '"}';
      for (final bad in <List<int>>[
        [0xC0, 0xAF], // overlong slash
        [0xED, 0xA0, 0x80], // a surrogate half written as 3 bytes
        [0xF0, 0x9F, 0x98], // cut off
        [0xFF],
      ]) {
        expect(
          () => decodeImport([
            ...utf8.encode(head),
            ...bad,
            ...utf8.encode(tail),
          ]),
          _rejected(ImportRejectReason.notUtf8),
          reason: '$bad',
        );
      }
    });

    test('UTF-16 text (what Notepad can save) is not UTF-8: refused', () {
      final text = jsonEncode(_file());
      final utf16 = <int>[
        0xFF,
        0xFE,
        for (final u in text.codeUnits) ...[u, 0],
      ];
      expect(() => decodeImport(utf16), _rejected());
    });

    test('a surrogate pair, as an escape or as raw UTF-8, is one emoji', () {
      final viaEscape = decodeImport(
        utf8.encode(
          '{"format":"kusunga-export","version":1,"snippets":[{"name":'
          '"\\ud83d\\ude00","content":"x\\ud83d\\ude80","type":"other"}]}',
        ),
      );
      final viaBytes = _decode(
        _file(
          snippets: [_snip(name: '😀', content: 'x🚀', type: 'other')],
        ),
      );
      expect(viaEscape.snippets.single.name, '😀');
      expect(viaEscape.snippets.single.content, 'x🚀');
      expect(viaBytes.snippets.single.name, viaEscape.snippets.single.name);
    });

    test('escaped NUL: allowed in snippet and history content, refused in a '
        'name and in a shortcut', () {
      final ok = _decode(
        _file(
          snippets: [_snip(content: 'a\u0000b')],
          history: [_clip(content: 'a\u0000b')],
        ),
      );
      expect(ok.snippets.single.content, 'a\u0000b');
      expect(ok.history!.single.content, 'a\u0000b');
      expect(
        () => _decode(_file(snippets: [_snip(name: 'a\u0000b')])),
        _rejected(),
      );
      expect(
        () => _decode(_file(snippets: [_snip(name: '\u0000')])),
        _rejected(),
      );
      expect(
        () => _decode(_file(snippets: [_snip(shortcut: ';a\u0000b')])),
        _rejected(),
      );
    });

    test('whatever the shape, only ImportRejected ever comes out', () {
      // Every top-level field set to every kind of wrong value.
      final wrongs = <Object?>[
        null,
        1,
        -1,
        1.5,
        'x',
        '',
        true,
        false,
        [],
        {},
        [[]],
        {'a': 1},
      ];
      for (final w in wrongs) {
        for (final field in [
          'snippets',
          'history',
          'settings',
          'ignored_apps',
          'exported_at',
        ]) {
          final m = _file()..[field] = w;
          try {
            _decode(m);
          } on ImportRejected {
            // expected for most
          }
        }
        for (final field in [
          'name',
          'content',
          'type',
          'shortcut',
          'position',
        ]) {
          final s = _snip()..[field] = w;
          try {
            _decode(_file(snippets: [s]));
          } on ImportRejected {
            // expected
          }
        }
        for (final field in [
          'content',
          'kind',
          'created_at',
          'last_copied_at',
        ]) {
          final h = _clip()..[field] = w;
          try {
            _decode(_file(history: [h]));
          } on ImportRejected {
            // expected
          }
        }
        for (final field in [
          'history_limit',
          'history_expiry_days',
          'typed_shortcuts_on',
          'paste_mode',
        ]) {
          try {
            _decode(_file(settings: {field: w}));
          } on ImportRejected {
            // expected
          }
        }
        for (final field in ['app_id', 'display_name']) {
          final a = <String, Object?>{'app_id': 'com.a', 'display_name': 'A'}
            ..[field] = w;
          try {
            _decode(_file(apps: [a]));
          } on ImportRejected {
            // expected
          }
        }
      }
    });
  });

  group('numbers and times', () {
    test('numbers given as text are refused: position, limits, switches', () {
      expect(
        () => _decode(_file(snippets: [_snip(position: '1')])),
        _rejected(),
      );
      expect(
        () => _decode(_file(settings: {'history_limit': '200'})),
        _rejected(),
      );
      expect(
        () => _decode(_file(settings: {'history_expiry_days': '30'})),
        _rejected(),
      );
      expect(
        () => _decode(_file(settings: {'typed_shortcuts_on': '1'})),
        _rejected(),
      );
      expect(
        () => _decode(_file(settings: {'typed_shortcuts_on': true})),
        _rejected(),
      );
    });

    test('a fractional or huge whole number is refused where a count is '
        'expected', () {
      expect(
        () => _decode(_file(settings: {'history_limit': 200.5})),
        _rejected(),
      );
      expect(
        () => decodeImport(
          utf8.encode(
            '{"format":"kusunga-export","version":1,"snippets":[],'
            '"settings":{"history_limit":99999999999999999999999}}',
          ),
        ),
        _rejected(),
      );
      expect(
        () => decodeImport(
          utf8.encode(
            '{"format":"kusunga-export","version":1,"snippets":[{"name":"A",'
            '"content":"c","type":"other","position":1e400}]}',
          ),
        ),
        _rejected(),
      );
    });

    test('positions: negative is refused; 0, a gap and the largest int are '
        'kept', () {
      expect(
        () => _decode(_file(snippets: [_snip(position: -1)])),
        _rejected(),
      );
      final b = decodeImport(
        utf8.encode(
          '{"format":"kusunga-export","version":1,"snippets":['
          '{"name":"A","content":"c","type":"other","position":9223372036854775807},'
          '{"name":"B","content":"c","type":"other"}]}',
        ),
      );
      expect(b.snippets[0].position, 9223372036854775807);
      expect(
        b.snippets[1].position,
        0,
        reason: 'a missing position reads as 0',
      );
    });

    test('settings at their edges: the smallest and largest allowed values '
        'pass, one outside refuses', () {
      final ok = _decode(
        _file(settings: {'history_limit': 10, 'history_expiry_days': 0}),
      );
      expect(ok.settings!.historyLimit, 10);
      expect(
        _decode(
          _file(settings: {'history_limit': 5000}),
        ).settings!.historyLimit,
        5000,
      );
      for (final bad in [9, 5001, 0, -1]) {
        expect(
          () => _decode(_file(settings: {'history_limit': bad})),
          _rejected(),
          reason: 'history_limit $bad',
        );
      }
      for (final bad in [-1, 2, 8, 29, 31, 366]) {
        expect(
          () => _decode(_file(settings: {'history_expiry_days': bad})),
          _rejected(),
          reason: 'history_expiry_days $bad',
        );
      }
      expect(
        () => _decode(_file(settings: {'typed_shortcuts_on': 2})),
        _rejected(),
      );
      expect(
        () => _decode(_file(settings: {'typed_shortcuts_on': -1})),
        _rejected(),
      );
      expect(
        () => _decode(_file(settings: {'paste_mode': 'AUTO'})),
        _rejected(),
      );
      expect(() => _decode(_file(settings: {'paste_mode': ''})), _rejected());
    });

    test('a setting the file must never carry is ignored, not applied', () {
      final b = _decode(
        _file(
          settings: {
            'history_limit': 50,
            'picker_shortcut': 'cmd+shift+x',
            'history_paused_until': 99999999999999,
          },
        ),
      );
      expect(b.settings!.historyLimit, 50);
      expect(b.settings!.isEmpty, isFalse);
      expect(b.hasSettings, isTrue);
    });

    test('timestamps far in the past and far in the future parse without '
        'error', () {
      final b = _decode(
        _file(
          history: [
            _clip(
              created: '0001-01-01T00:00:00Z',
              last: '0001-01-02T00:00:00Z',
            ),
            _clip(
              content: 'future',
              created: '9999-12-31T23:59:59Z',
              last: '9999-12-31T23:59:59Z',
            ),
          ],
        ),
      );
      expect(b.history![0].lastCopiedAt, isNegative);
      expect(b.history![1].lastCopiedAt, greaterThan(250000000000000));
    });

    test('timestamps that are not times are refused', () {
      for (final bad in ['', 'yesterday', 12345, null, true]) {
        expect(
          () => _decode(_file(history: [_clip(last: bad)])),
          _rejected(),
          reason: '$bad',
        );
        expect(
          () => _decode(_file(history: [_clip(created: bad)])),
          _rejected(),
          reason: '$bad',
        );
      }
    });

    test('last_copied_at before created_at is read as it is (no check)', () {
      final b = _decode(
        _file(
          history: [
            _clip(
              created: '2026-11-10T00:00:00Z',
              last: '2026-11-01T00:00:00Z',
            ),
          ],
        ),
      );
      expect(
        b.history!.single.lastCopiedAt,
        lessThan(b.history!.single.createdAt),
      );
    });
  });

  group('field limits, exactly', () {
    test('snippet names of 0, 1, 100 and 101 characters', () {
      expect(() => _decode(_file(snippets: [_snip(name: '')])), _rejected());
      expect(
        _decode(_file(snippets: [_snip(name: 'a')])).snippets,
        hasLength(1),
      );
      expect(
        _decode(_file(snippets: [_snip(name: 'a' * 100)])).snippets,
        hasLength(1),
      );
      expect(
        () => _decode(_file(snippets: [_snip(name: 'a' * 101)])),
        _rejected(),
      );
    });

    test('names count characters, not UTF-16 units: 100 emoji pass, 101 '
        'refuse', () {
      expect(
        _decode(_file(snippets: [_snip(name: '😀' * 100)])).snippets,
        hasLength(1),
      );
      expect(
        () => _decode(_file(snippets: [_snip(name: '😀' * 101)])),
        _rejected(),
      );
    });

    test('names must already be one clean line: padding, line breaks and '
        'invisible-only names are refused', () {
      for (final bad in [' a', 'a ', 'a\nb', 'a\r\nb', '\u200B', '   ', '\t']) {
        expect(
          () => _decode(_file(snippets: [_snip(name: bad)])),
          _rejected(),
          reason: jsonEncode(bad),
        );
      }
    });

    test('snippet content at the size limit passes, one byte over refuses; '
        'blank content refuses', () {
      final max = ClipItem.maxContentLength;
      expect(
        _decode(
          _file(snippets: [_snip(content: 'a' * max)]),
        ).snippets.single.content.length,
        max,
      );
      expect(
        () => _decode(_file(snippets: [_snip(content: 'a' * (max + 1))])),
        _rejected(),
      );
      // 3-byte characters: the limit is in bytes, not characters.
      final euro = '€' * (max ~/ 3); // 1,048,575 bytes
      expect(
        _decode(_file(snippets: [_snip(content: euro)])).snippets,
        hasLength(1),
      );
      expect(
        () => _decode(_file(snippets: [_snip(content: '$euro€')])),
        _rejected(),
      );
      expect(() => _decode(_file(snippets: [_snip(content: '')])), _rejected());
      expect(
        () => _decode(_file(snippets: [_snip(content: ' \n\t ')])),
        _rejected(),
      );
    });

    test('history content at the size limit passes, one byte over refuses, '
        'empty refuses', () {
      final max = ClipItem.maxContentLength;
      expect(
        _decode(_file(history: [_clip(content: 'a' * max)])).history,
        hasLength(1),
      );
      expect(
        () => _decode(_file(history: [_clip(content: 'a' * (max + 1))])),
        _rejected(),
      );
      expect(() => _decode(_file(history: [_clip(content: '')])), _rejected());
    });

    test('exactly 1,000 snippets pass; 1,001 refuse; exactly 5,000 history '
        'items pass; 5,001 refuse', () {
      List<Map<String, Object?>> snips(int n) => [
        for (var i = 0; i < n; i++)
          _snip(name: 'n$i', content: 'c$i', position: i),
      ];
      List<Map<String, Object?>> clips(int n) => [
        for (var i = 0; i < n; i++) _clip(content: 'item $i'),
      ];
      expect(_decode(_file(snippets: snips(1000))).snippets, hasLength(1000));
      expect(() => _decode(_file(snippets: snips(1001))), _rejected());
      expect(_decode(_file(history: clips(5000))).history, hasLength(5000));
      expect(() => _decode(_file(history: clips(5001))), _rejected());
    });

    test('ignored app ids: empty and over 255 are refused, 1 and 255 pass; '
        'a blank display name is judged by the app rule', () {
      List<Map<String, String>> app(String id, [String name = 'A']) => [
        {'app_id': id, 'display_name': name},
      ];
      expect(() => _decode(_file(apps: app(''))), _rejected());
      expect(() => _decode(_file(apps: app('a' * 256))), _rejected());
      expect(_decode(_file(apps: app('a'))).ignoredApps, hasLength(1));
      expect(_decode(_file(apps: app('a' * 255))).ignoredApps, hasLength(1));
      expect(
        () => _decode(_file(apps: app('com.a', 'x' * 100000))),
        _rejected(),
      );
    });

    test('shortcuts: spaces, controls, lone surrogates, 1 and 33 characters '
        'are refused; 2 and 32 pass', () {
      Object? sc(String s) => _snip(shortcut: s);
      for (final bad in [
        'a',
        ';a b',
        ';a\n',
        ';\u0007x',
        'a' * 33,
        '${'\u{1F600}'.substring(0, 1)}ab',
      ]) {
        expect(
          () => _decode(_file(snippets: [sc(bad)])),
          _rejected(),
          reason: jsonEncode(bad),
        );
      }
      expect(
        _decode(_file(snippets: [sc(';p')])).snippets.single.shortcut,
        ';p',
      );
      expect(_decode(_file(snippets: [sc(';' * 32)])).snippets, hasLength(1));
      // emoji count as one character each
      expect(_decode(_file(snippets: [sc('😀' * 32)])).snippets, hasLength(1));
      expect(() => _decode(_file(snippets: [sc('😀' * 33)])), _rejected());
    });

    test('unknown snippet types and history kinds are refused, any case', () {
      expect(
        () => _decode(_file(snippets: [_snip(type: 'Phone')])),
        _rejected(),
      );
      expect(
        () => _decode(_file(snippets: [_snip(type: 'secret')])),
        _rejected(),
      );
      expect(() => _decode(_file(history: [_clip(kind: 'TEXT')])), _rejected());
      expect(
        () => _decode(_file(history: [_clip(kind: 'script')])),
        _rejected(),
      );
    });

    test('paths and commands inside a file are plain text, never opened', () {
      final b = _decode(
        _file(
          snippets: [
            _snip(
              name: '../../etc/passwd',
              content: r'$(rm -rf ~) `x` file:///etc/hosts',
            ),
          ],
          apps: [
            {'app_id': '../../../x', 'display_name': 'C:\\Windows\\System32'},
          ],
        ),
      );
      expect(b.snippets.single.name, '../../etc/passwd');
      expect(b.ignoredApps!.single.appId, '../../../x');
    });
  });

  group('bugs found', () {
    test('BUG-T1 (Low): a history item that is only white space is refused '
        'like capture refuses it', () {
      // HistoryService never keeps a copy whose text is blank
      // (text.trim().isEmpty), and snippets refuse blank content, but the
      // import accepts "   " as a history item.
      expect(
        () => _decode(_file(history: [_clip(content: '   \n\t ')])),
        _rejected(),
      );
    });

    test(
      'BUG-T2 (Low): a lone surrogate in text is refused or stays exactly as '
      'it was; it is never silently changed on its way into the file',
      () {
        // "\ud800" decodes to a lone UTF-16 surrogate. SQLite stores UTF-8,
        // where it can only become U+FFFD, so the saved snippet differs from
        // the one in the file and a second import of the same file would
        // compare the changed text. Shortcuts already refuse a lone
        // surrogate (T2 of M1.5); names and content do not.
        const text =
            '{"format":"kusunga-export","version":1,"snippets":[{"name":"A",'
            '"content":"x\\ud800y","type":"other"}]}';
        try {
          final b = decodeImport(utf8.encode(text));
          // Accepted: it must survive a UTF-8 round trip unchanged.
          final c = b.snippets.single.content;
          expect(utf8.decode(utf8.encode(c)), c);
        } on ImportRejected {
          // refused: fine
        }
      },
    );

    test('BUG-T9 (Low): a time that does not exist (month 13, 31 February) is '
        'refused, not moved to another day', () {
      // DateTime.tryParse rolls 2026-13-45 over to a later date and
      // 2026-02-31 to 2026-03-03, so a damaged file's times are quietly
      // changed instead of the file being refused.
      for (final bad in ['2026-13-45T00:00:00Z', '2026-02-31T00:00:00Z']) {
        expect(
          () => _decode(_file(history: [_clip(last: bad)])),
          _rejected(),
          reason: bad,
        );
      }
    });

    test('BUG-T3 (Low): a typed_shortcuts_on written as 1.0 or 0.0 is refused '
        'like any other number that is not 0 or 1', () {
      // 1.0 == 1 in Dart, so `typed != 0 && typed != 1` lets doubles
      // through; history_limit and the version refuse 200.0 and 1.0.
      expect(
        () => decodeImport(
          utf8.encode(
            '{"format":"kusunga-export","version":1,"snippets":[],'
            '"settings":{"typed_shortcuts_on":1.0}}',
          ),
        ),
        _rejected(),
      );
    });
  });
}
