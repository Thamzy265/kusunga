// M1.8 export file format and import checks (docs/design/your-data.md,
// "Export file", "Import", "Trust boundaries and abuse cases").
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/snippet.dart';

final _at = DateTime.utc(2026, 11, 12, 9, 30);

ExportBundle _bundle({bool history = true}) => ExportBundle(
  snippets: const [
    ExportSnippet(
      name: 'Phone',
      content: '+44 20 7946 0000',
      type: SnippetType.phone,
      shortcut: ';ph',
      position: 0,
    ),
    ExportSnippet(
      name: 'Email',
      content: 'a@example.com',
      type: SnippetType.email,
      position: 1,
    ),
  ],
  history: history
      ? [
          ExportHistoryItem(
            content: 'https://example.com',
            kind: ClipKind.link,
            createdAt: _at.millisecondsSinceEpoch - 5000,
            lastCopiedAt: _at.millisecondsSinceEpoch - 1000,
          ),
        ]
      : null,
  settings: const ExportSettings(
    historyLimit: 300,
    historyExpiryDays: 7,
    typedShortcutsOn: true,
    pasteMode: 'copy_only',
  ),
  ignoredApps: const [IgnoredApp('com.example.vault', 'Vault')],
);

Map<String, Object?> _json(ExportBundle b) =>
    jsonDecode(encodeExport(b, exportedAt: _at)) as Map<String, Object?>;

List<int> _bytes(Object? json) => utf8.encode(jsonEncode(json));

/// A valid file as JSON, to break one field at a time.
Map<String, Object?> _valid() => _json(_bundle());

Matcher _rejected(ImportRejectReason reason) =>
    throwsA(isA<ImportRejected>().having((e) => e.reason, 'reason', reason));

void main() {
  group('export', () {
    test('writes the approved shape with format, version and UTC time', () {
      final json = _json(_bundle());
      expect(json['format'], 'kusunga-export');
      expect(json['version'], 1);
      expect(json['exported_at'], '2026-11-12T09:30:00.000Z');
      expect(json['snippets'], [
        {
          'name': 'Phone',
          'content': '+44 20 7946 0000',
          'type': 'phone',
          'shortcut': ';ph',
          'position': 0,
        },
        {
          'name': 'Email',
          'content': 'a@example.com',
          'type': 'email',
          'shortcut': null,
          'position': 1,
        },
      ]);
      expect((json['history'] as List).single, {
        'content': 'https://example.com',
        'kind': 'link',
        'created_at': '2026-11-12T09:29:55.000Z',
        'last_copied_at': '2026-11-12T09:29:59.000Z',
      });
      expect(json['settings'], {
        'history_limit': 300,
        'history_expiry_days': 7,
        'typed_shortcuts_on': 1,
        'paste_mode': 'copy_only',
      });
      expect(json['ignored_apps'], [
        {'app_id': 'com.example.vault', 'display_name': 'Vault'},
      ]);
    });

    test('no history key at all when history is not included (D2)', () {
      expect(_json(_bundle(history: false)).containsKey('history'), isFalse);
    });

    test('never the picker shortcut or the pause (lead ruling G1)', () {
      final text = encodeExport(_bundle(), exportedAt: _at);
      expect(text, isNot(contains('picker_shortcut')));
      expect(text, isNot(contains('history_paused_until')));
    });

    test('default file name is kusunga-export-YYYY-MM-DD.json', () {
      expect(
        exportFileName(DateTime(2026, 3, 4, 23, 59)),
        'kusunga-export-2026-03-04.json',
      );
    });
  });

  group('round trip', () {
    test('decode(encode(x)) gives the same data', () {
      final b = _bundle();
      final back = decodeImport(utf8.encode(encodeExport(b, exportedAt: _at)));
      expect(back.snippets.length, 2);
      for (var i = 0; i < 2; i++) {
        expect(back.snippets[i].name, b.snippets[i].name);
        expect(back.snippets[i].content, b.snippets[i].content);
        expect(back.snippets[i].type, b.snippets[i].type);
        expect(back.snippets[i].shortcut, b.snippets[i].shortcut);
        expect(back.snippets[i].position, b.snippets[i].position);
      }
      final h = back.history!.single;
      expect(h.content, 'https://example.com');
      expect(h.kind, ClipKind.link);
      expect(h.createdAt, b.history!.single.createdAt);
      expect(h.lastCopiedAt, b.history!.single.lastCopiedAt);
      expect(back.settings!.historyLimit, 300);
      expect(back.settings!.historyExpiryDays, 7);
      expect(back.settings!.typedShortcutsOn, isTrue);
      expect(back.settings!.pasteMode, 'copy_only');
      expect(back.ignoredApps!.single.appId, 'com.example.vault');
      expect(back.ignoredApps!.single.displayName, 'Vault');
    });

    test('text that is not ASCII survives (emoji, accents, NUL, RTL)', () {
      const odd = 'Zoë 😀 \u0000 \u202Eabc ñ';
      final b = ExportBundle(
        snippets: const [
          ExportSnippet(
            name: 'Zoë 😀',
            content: odd,
            type: SnippetType.other,
            position: 0,
          ),
        ],
        history: [
          ExportHistoryItem(
            content: odd,
            kind: ClipKind.text,
            createdAt: 1,
            lastCopiedAt: 2,
          ),
        ],
      );
      final back = decodeImport(utf8.encode(encodeExport(b, exportedAt: _at)));
      expect(back.snippets.single.content, odd);
      expect(back.snippets.single.name, 'Zoë 😀');
      expect(back.history!.single.content, odd);
    });

    test(
      'a file with only settings and no snippets still exports and reads',
      () {
        const b = ExportBundle(snippets: [], settings: ExportSettings());
        final back = decodeImport(
          utf8.encode(encodeExport(b, exportedAt: _at)),
        );
        expect(back.snippets, isEmpty);
        expect(back.history, isNull);
      },
    );
  });

  group('import refuses the whole file', () {
    test('over 20 MB, before it is parsed', () {
      final big = List<int>.filled(maxImportBytes + 1, 0x20);
      expect(() => decodeImport(big), _rejected(ImportRejectReason.tooLarge));
    });

    test('exactly 20 MB is not refused for its size', () {
      final head = utf8.encode(jsonEncode(_valid()));
      final bytes = [
        ...head,
        ...List<int>.filled(maxImportBytes - head.length, 0x20),
      ];
      expect(bytes.length, maxImportBytes);
      expect(decodeImport(bytes).snippets, hasLength(2));
    });

    test('not UTF-8', () {
      final bytes = [..._bytes(_valid())];
      // Latin-1 é inside a string: 0xE9 is not valid UTF-8 here.
      final i = bytes.indexOf(utf8.encode('Phone').first);
      bytes[i] = 0xE9;
      expect(() => decodeImport(bytes), _rejected(ImportRejectReason.notUtf8));
      expect(
        () => decodeImport([0xFF, 0xFE, 0x7B, 0x00, 0x7D, 0x00]),
        _rejected(ImportRejectReason.notUtf8),
      );
    });

    test('a UTF-8 byte order mark is allowed', () {
      expect(
        decodeImport([0xEF, 0xBB, 0xBF, ..._bytes(_valid())]).snippets,
        hasLength(2),
      );
    });

    test('not JSON, empty, or not an object', () {
      for (final text in [
        '',
        'hello',
        '{"format":',
        '[]',
        '"x"',
        '1',
        'null',
      ]) {
        expect(
          () => decodeImport(utf8.encode(text)),
          _rejected(ImportRejectReason.notJson),
          reason: text,
        );
      }
    });

    test('deep nesting is refused before the parser recurses', () {
      final deep = '${'[' * 100000}${']' * 100000}';
      final text = '{"format":"kusunga-export","version":1,"x":$deep}';
      expect(
        () => decodeImport(utf8.encode(text)),
        _rejected(ImportRejectReason.tooDeep),
      );
      // Brackets inside strings do not count.
      final inString = _valid()..['note'] = '[' * 1000;
      expect(decodeImport(_bytes(inString)).snippets, hasLength(2));
    });

    test('the wrong format name, or none', () {
      for (final f in ['other-app', null, 1, 'KUSUNGA-EXPORT']) {
        final json = _valid()..['format'] = f;
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.wrongFormat),
          reason: '$f',
        );
      }
    });

    test('a higher version than Kusunga knows', () {
      final json = _valid()..['version'] = 2;
      expect(
        () => decodeImport(_bytes(json)),
        _rejected(ImportRejectReason.newerVersion),
      );
    });

    test('a version that is not a whole number from 1', () {
      for (final v in [0, -1, '1', 1.5, null]) {
        final json = _valid()..['version'] = v;
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.wrongFormat),
          reason: '$v',
        );
      }
    });

    void badSnippet(String why, void Function(Map<String, Object?> s) change) {
      test('a snippet with $why', () {
        final json = _valid();
        final s = (json['snippets'] as List).first as Map<String, Object?>;
        change(s);
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.badItem),
        );
      });
    }

    badSnippet('a name over 100 characters', (s) => s['name'] = 'n' * 101);
    badSnippet('an empty name', (s) => s['name'] = '');
    badSnippet('an invisible name', (s) => s['name'] = '​​');
    badSnippet('a name with a line break', (s) => s['name'] = 'a\nb');
    badSnippet('no name', (s) => s.remove('name'));
    badSnippet('a name that is a number', (s) => s['name'] = 5);
    badSnippet('empty content', (s) => s['content'] = '   ');
    badSnippet(
      'content over 1 MiB',
      (s) => s['content'] = 'x' * (ClipItem.maxContentLength + 1),
    );
    badSnippet('an unknown type', (s) => s['type'] = 'password');
    badSnippet('half a character in its name (T2)', (s) {
      s['name'] = 'a\ud800b';
    });
    badSnippet('half a character in its content (T2)', (s) {
      s['content'] = 'x\udc00';
    });
    badSnippet('a shortcut with a space', (s) => s['shortcut'] = '; ph');
    badSnippet('a one-character shortcut', (s) => s['shortcut'] = ';');
    badSnippet('a 33-character shortcut', (s) => s['shortcut'] = ';' * 33);
    badSnippet('a shortcut with a tab', (s) => s['shortcut'] = ';p\th');
    badSnippet('a shortcut that is a number', (s) => s['shortcut'] = 12);
    badSnippet('a negative position', (s) => s['position'] = -1);
    badSnippet('a position that is text', (s) => s['position'] = '0');

    test('a snippet that is not an object, or snippets not a list', () {
      for (final v in <Object?>[
        ['x'],
        'x',
        null,
        {'a': 1},
      ]) {
        final json = _valid()..['snippets'] = v;
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.badItem),
          reason: '$v',
        );
      }
    });

    test('more than 1,000 snippets', () {
      final json = _valid()
        ..['snippets'] = [
          for (var i = 0; i < 1001; i++)
            {'name': 'n$i', 'content': 'c', 'type': 'other', 'position': i},
        ];
      expect(
        () => decodeImport(_bytes(json)),
        _rejected(ImportRejectReason.badItem),
      );
    });

    void badHistory(String why, void Function(Map<String, Object?> h) change) {
      test('a history item with $why', () {
        final json = _valid();
        final h = (json['history'] as List).first as Map<String, Object?>;
        change(h);
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.badItem),
        );
      });
    }

    badHistory('empty content', (h) => h['content'] = '');
    badHistory('content that is only white space (T1)', (h) {
      h['content'] = ' \n\t\r ';
    });
    badHistory('content that is only no-break and wide spaces (T1)', (h) {
      h['content'] = '\u00a0\u2003\ufeff';
    });
    badHistory(
      'content over 1 MiB of UTF-8',
      (h) => h['content'] = 'é' * (ClipItem.maxContentLength ~/ 2 + 1),
    );
    badHistory('an unknown kind', (h) => h['kind'] = 'image');
    badHistory('half a character at the end (T2)', (h) {
      h['content'] = 'text\ud83d';
    });
    badHistory('the halves of a character the wrong way round (T2)', (h) {
      h['content'] = '\ude00\ud83d';
    });
    badHistory('a time that does not parse', (h) => h['created_at'] = 'soon');
    badHistory('a time that is a number', (h) => h['last_copied_at'] = 5);
    badHistory('no time', (h) => h.remove('last_copied_at'));

    test('more than 5,000 history items', () {
      final json = _valid()
        ..['history'] = [
          for (var i = 0; i < 5001; i++)
            {
              'content': 'c$i',
              'kind': 'text',
              'created_at': '2026-01-01T00:00:00Z',
              'last_copied_at': '2026-01-01T00:00:00Z',
            },
        ];
      expect(
        () => decodeImport(_bytes(json)),
        _rejected(ImportRejectReason.badItem),
      );
    });

    void badSetting(String key, Object? value) {
      test('setting $key = $value', () {
        final json = _valid();
        (json['settings'] as Map<String, Object?>)[key] = value;
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.badItem),
        );
      });
    }

    badSetting('history_limit', 9);
    badSetting('history_limit', 5001);
    badSetting('history_limit', '200');
    badSetting('history_limit', 200.5);
    badSetting('history_expiry_days', 2);
    badSetting('history_expiry_days', -1);
    badSetting('typed_shortcuts_on', 2);
    badSetting('typed_shortcuts_on', true);
    badSetting('typed_shortcuts_on', 1.0); // T3
    badSetting('typed_shortcuts_on', 0.0); // T3
    badSetting('typed_shortcuts_on', '1');
    badSetting('paste_mode', 'sometimes');
    badSetting('paste_mode', 'a' * 100000);

    test('settings that are not an object', () {
      final json = _valid()..['settings'] = [1];
      expect(
        () => decodeImport(_bytes(json)),
        _rejected(ImportRejectReason.badItem),
      );
    });

    void badApp(String why, Map<String, Object?> app) {
      test('an ignored app with $why', () {
        final json = _valid()..['ignored_apps'] = [app];
        expect(
          () => decodeImport(_bytes(json)),
          _rejected(ImportRejectReason.badItem),
        );
      });
    }

    badApp('an id of 256 characters', {
      'app_id': 'a' * 256,
      'display_name': 'A',
    });
    badApp('an empty id', {'app_id': '', 'display_name': 'A'});
    badApp('a name over 100 characters', {
      'app_id': 'a',
      'display_name': 'n' * 101,
    });
    badApp('no name', {'app_id': 'a'});
    badApp('half a character in its id (T2)', {
      'app_id': 'com.a\ud800',
      'display_name': 'A',
    });
    badApp('half a character in its name (T2)', {
      'app_id': 'com.a',
      'display_name': '\udfff',
    });
  });

  group('import reads only what it knows', () {
    test('unknown fields are ignored, at every level', () {
      final json = _valid()
        ..['path'] = '/etc/passwd'
        ..['run'] = 'rm -rf /';
      (json['snippets'] as List).cast<Map<String, Object?>>().first['x'] = 1;
      (json['settings'] as Map<String, Object?>)['picker_shortcut'] = 'cmd+v';
      (json['settings'] as Map<String, Object?>)['history_paused_until'] = -1;
      final b = decodeImport(_bytes(json));
      expect(b.snippets, hasLength(2));
      expect(b.settings!.historyLimit, 300);
    });

    test('history text with white space around it is kept exactly as it '
        'is (T1)', () {
      final json = _valid();
      ((json['history'] as List).first as Map<String, Object?>)['content'] =
          '  a\n ';
      expect(decodeImport(_bytes(json)).history!.single.content, '  a\n ');
    });

    test('whole characters made of two halves (emoji) are kept exactly '
        '(T2)', () {
      final json = _valid();
      final s = (json['snippets'] as List).first as Map<String, Object?>;
      s['name'] = 'Smile 😀';
      s['content'] = '👨‍👩‍👧 🇬🇧';
      final b = decodeImport(_bytes(json));
      expect(b.snippets.first.name, 'Smile 😀');
      expect(b.snippets.first.content, '👨‍👩‍👧 🇬🇧');
    });

    test('an app id of exactly 255 characters is fine', () {
      final json = _valid()
        ..['ignored_apps'] = [
          {'app_id': 'a' * 255, 'display_name': 'A'},
        ];
      expect(decodeImport(_bytes(json)).ignoredApps!.single.appId.length, 255);
    });

    test('missing optional parts: history, settings, ignored apps', () {
      final json = _valid()
        ..remove('history')
        ..remove('settings')
        ..remove('ignored_apps');
      final b = decodeImport(_bytes(json));
      expect(b.history, isNull);
      expect(b.settings, isNull);
      expect(b.ignoredApps, isNull);
      expect(b.hasSettings, isFalse);
    });

    test('settings with only some keys keep the others null', () {
      final json = _valid()..['settings'] = {'history_limit': 10};
      final s = decodeImport(_bytes(json)).settings!;
      expect(s.historyLimit, 10);
      expect(s.historyExpiryDays, isNull);
      expect(s.typedShortcutsOn, isNull);
      expect(s.pasteMode, isNull);
    });
  });
}
