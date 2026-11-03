// Tester (M1.2): abuse cases from "Trust boundaries and abuse cases" in
// docs/design/clipboard-history.md, at the size limit, in link detection and
// in how odd characters are shown. Run against both stores.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/clip_classifier.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/history/ui/text_display.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  group('link detection edge cases', () {
    test('only a single http or https address is a link', () {
      const text = [
        'javascript:alert(1)',
        'JAVASCRIPT://example.com/%0Aalert(1)',
        'file:///etc/passwd',
        'FILE://host/share',
        'ftp://example.com',
        'data:text/html,<script>alert(1)</script>',
        'vbscript:msgbox(1)',
        'mailto:a@example.com',
        'http://',
        'https:///path-only',
        'http:example.com',
        'https:/example.com',
        '//example.com',
        'example.com',
        'www.example.com',
        'https://exa mple.com',
        'https://example.com/a b',
        'https://example.com\nhttps://evil.example',
        'https://example.com\thttps://evil.example',
        'https://example.com evil',
        'see https://example.com',
        'http://[::1',
        '',
        '   ',
      ];
      for (final s in text) {
        expect(classify(s), ClipKind.text, reason: 'input: ${_show(s)}');
      }
    });

    test('an uppercase or mixed-case scheme is still a link', () {
      expect(classify('HTTPS://EXAMPLE.COM/Path'), ClipKind.link);
      expect(classify('HtTp://example.com'), ClipKind.link);
    });

    test('surrounding whitespace does not stop a link being a link', () {
      expect(classify('  https://example.com/a?b=c#d \n'), ClipKind.link);
    });

    test('ports, credentials, IPv6 and localhost are links', () {
      expect(classify('http://localhost:8080/x'), ClipKind.link);
      expect(classify('http://[::1]:3000/'), ClipKind.link);
      expect(classify('https://user:pw@example.com/'), ClipKind.link);
    });

    test('classify never throws on hostile input', () {
      final hostile = [
        '%',
        'http://%zz',
        'https://%',
        'http://\u0000',
        'http://${'a' * 100000}.com',
        '\u{1F600}' * 1000,
        'https://example.com/${'%41' * 50000}',
      ];
      for (final s in hostile) {
        expect(() => classify(s), returnsNormally, reason: _show(s));
      }
    });
  });

  group('control, bidi and invisible characters are made visible', () {
    test('every bidi control is replaced by a visible code', () {
      const bidi = [
        0x061C,
        0x200E,
        0x200F,
        0x202A,
        0x202B,
        0x202C,
        0x202D,
        0x202E,
        0x2066,
        0x2067,
        0x2068,
        0x2069,
      ];
      for (final cp in bidi) {
        final shown = visibleText('a${String.fromCharCode(cp)}b');
        expect(shown, contains('[U+'), reason: cp.toRadixString(16));
        expect(shown.runes, isNot(contains(cp)), reason: cp.toRadixString(16));
      }
    });

    test('every C0 control except tab and newline becomes a picture', () {
      for (var cp = 0; cp < 0x20; cp++) {
        if (cp == 0x09 || cp == 0x0A) continue;
        final shown = visibleText('a${String.fromCharCode(cp)}b');
        expect(shown.runes.toList(), [
          0x61,
          0x2400 + cp,
          0x62,
        ], reason: 'U+${cp.toRadixString(16)}');
      }
      expect(visibleText('a\u007Fb'), 'a␡b');
    });

    test('every C1 control is shown as a code', () {
      for (var cp = 0x80; cp <= 0x9F; cp++) {
        final shown = visibleText('a${String.fromCharCode(cp)}b');
        expect(shown, startsWith('a[U+'), reason: cp.toRadixString(16));
      }
    });

    test('a carriage return alone is visible; CR LF is one newline', () {
      expect(visibleText('a\rb'), 'a␍b');
      expect(visibleText('a\r\nb'), 'a\nb');
    });

    test('zero width characters and the byte order mark are visible', () {
      for (final cp in [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]) {
        expect(
          visibleText('a${String.fromCharCode(cp)}b'),
          contains('[U+'),
          reason: cp.toRadixString(16),
        );
      }
    });

    test('line and paragraph separators cannot fake extra lines', () {
      // U+2028 and U+2029 start a new line in most text engines, so they
      // can make a row look like two separate entries.
      for (final cp in [0x2028, 0x2029]) {
        final shown = visibleText('a${String.fromCharCode(cp)}b');
        expect(shown.runes, isNot(contains(cp)), reason: cp.toRadixString(16));
      }
    });

    test('Unicode tag characters (invisible text) are visible', () {
      // U+E0000-E007F render as nothing but carry ASCII-like payloads.
      final hidden = String.fromCharCodes([0xE0001, 0xE0041, 0xE0042, 0xE007F]);
      final shown = visibleText('hello$hidden');
      for (final cp in hidden.runes) {
        expect(shown.runes, isNot(contains(cp)), reason: cp.toRadixString(16));
      }
    });

    test('a hostile string never keeps a raw bidi override', () {
      const trick = 'invoice\u202Efdp.exe\u202C \u2066 \u2069';
      final shown = visibleText(trick);
      expect(shown.contains(RegExp('[\u202A-\u202E\u2066-\u2069]')), isFalse);
    });

    test('ordinary text, emoji, accents and right-to-left letters pass', () {
      const fine = 'Café 日本語 שלום مرحبا \u{1F468}\u200D\u{1F469}x';
      // The zero width joiner between two emoji (one family emoji) stays
      // (BUG-V1; this used to expect a code): the rest must be untouched.
      final shown = visibleText(fine);
      expect(shown, contains('Café 日本語 שלום مرحبا'));
      expect(shown, contains('\u{1F468}\u200D\u{1F469}x'));
      expect(shown, isNot(contains('[U+200D]')));
    });

    test('visibleText never throws on a lone surrogate', () {
      expect(() => visibleText('a\uD800b'), returnsNormally);
      expect(() => visibleText('\uDC00'), returnsNormally);
    });
  });

  group('the 1 MB limit', () {
    late Directory dir;
    late FakeClipboardSource source;
    late FakeLog log;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('kusunga_abuse_');
      source = FakeClipboardSource();
      log = FakeLog();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    HistoryStore memory() => MemoryHistoryStore();
    HistoryStore sqlite() =>
        SqliteHistoryStore.open(path: '${dir.path}/k.db', keyHex: _key);

    for (final name in ['memory', 'sqlite']) {
      group(name, () {
        late HistoryStore store;
        late HistoryService service;
        setUp(() {
          store = name == 'memory' ? memory() : sqlite();
          service = HistoryService(
            store: store,
            source: source,
            log: log,
            clock: () => 1000,
            writeClipboard: (_) async {},
          )..start();
        });
        tearDown(() {
          service.dispose();
          store.close();
        });

        test('exactly 1,048,576 characters is saved, one more is not', () {
          source.copy('a' * ClipItem.maxContentLength);
          expect(store.count, 1);
          source.copy('b' * (ClipItem.maxContentLength + 1));
          expect(store.count, 1, reason: 'no part of the large copy is kept');
          expect(
            store.list().single.preview.startsWith('b'),
            isFalse,
            reason: 'nothing of the large copy is stored',
          );
          expect(log.codes, [LogCode.clipboardTooLarge]);
        });

        // Lead decision (M1.2 fixes): the cap is 1 MiB of UTF-8 bytes, not
        // characters, so the design's 50 MB worst case holds. These two tests
        // assumed characters; they now count bytes.
        test('4-byte emoji: 262,144 fit (1 MiB of UTF-8), 262,145 do not', () {
          source.copy('\u{1F600}' * 262144);
          expect(store.count, 1);
          source.copy('\u{1F601}' * 262145);
          expect(store.count, 1);
          expect(log.codes, [LogCode.clipboardTooLarge]);
        });

        test('3-byte characters: 349,525 fit, 349,526 do not', () {
          final fits = '€' * 349525;
          source.copy(fits);
          expect(store.count, 1);
          expect(store.contentOf(store.list().single.id), fits);
          source.copy('€' * 349526);
          expect(store.count, 1);
          expect(log.codes, [LogCode.clipboardTooLarge]);
        });

        test('a huge copy leaves the history and the log untouched', () {
          source.copy('keep me');
          source.copy('x' * 5000000);
          expect(store.list().map((i) => i.preview), ['keep me']);
          expect(log.codes, [LogCode.clipboardTooLarge]);
        });

        test('a native tooLarge event stores nothing and logs a code', () {
          source.controller.add(const ClipboardSkipped(SkipReason.tooLarge));
          expect(store.count, 0);
          expect(log.codes, [LogCode.clipboardTooLarge]);
        });
      });
    }
  });

  for (final (name, create) in <(String, HistoryStore Function(Directory))>[
    ('MemoryHistoryStore', (_) => MemoryHistoryStore()),
    (
      'SqliteHistoryStore',
      (d) => SqliteHistoryStore.open(path: '${d.path}/k.db', keyHex: _key),
    ),
  ]) {
    group('$name with hostile text', () {
      late Directory dir;
      late HistoryStore store;
      setUp(() {
        dir = Directory.systemTemp.createTempSync('kusunga_hostile_');
        store = create(dir);
      });
      tearDown(() {
        store.close();
        dir.deleteSync(recursive: true);
      });

      test('text that starts with NUL is saved and read back whole', () {
        // Bug repro (BUG-1): SQLite length() stops at the first NUL, so
        // the CHECK (length BETWEEN 1 AND ...) fails and the insert throws.
        const text = '\u0000secret-tail';
        final id = store.insertOrBump(text, ClipKind.text, 1);
        expect(store.contentOf(id), text);
      });

      test('text that is only NUL is saved and read back whole', () {
        final id = store.insertOrBump('\u0000', ClipKind.text, 1);
        expect(store.contentOf(id), '\u0000');
      });

      test('the list preview of text with a NUL inside is not cut at it', () {
        // Bug repro (BUG-2): substr() in SQL stops at the NUL, so the row
        // shows "ab" for "ab<NUL>cd" while the memory store shows all.
        const text = 'ab\u0000cd';
        store.insertOrBump(text, ClipKind.text, 1);
        expect(store.list().single.preview, text);
      });

      test('the preview is at most 2,000 UTF-16 units, emoji included', () {
        // Bug repro (BUG-3): SQL substr() counts code points, not UTF-16
        // units, so 1,500 emoji (3,000 units) are not cut or marked
        // truncated; the memory store cuts them at 2,000 units.
        final text = '\u{1F600}' * 1500;
        store.insertOrBump(text, ClipKind.text, 1);
        final item = store.list().single;
        expect(item.preview.length, lessThanOrEqualTo(ClipItem.previewLength));
        expect(item.isTruncated, isTrue);
        expect(item.preview.codeUnits.last & 0xFC00, isNot(0xD800));
      });

      test('a preview never ends in half an emoji', () {
        // 1,999 letters then an emoji whose first half is the 2,000th unit.
        final text = '${'a' * 1999}\u{1F600}tail';
        store.insertOrBump(text, ClipKind.text, 1);
        final last = store.list().single.preview.codeUnits.last;
        expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
      });

      test('SQL-looking text is stored as plain data', () {
        const sql = "'); DROP TABLE clip_items; --";
        store.insertOrBump(sql, ClipKind.text, 1);
        store.insertOrBump('after', ClipKind.text, 2);
        expect(store.count, 2);
        expect(store.contentOf(store.list().last.id), sql);
      });

      test('HTML and markdown are stored and returned as the typed text', () {
        const html = '<script>alert(1)</script><b>bold</b> **md** [x](y)';
        final id = store.insertOrBump(html, ClipKind.text, 1);
        expect(store.contentOf(id), html);
        expect(store.list().single.kind, ClipKind.text);
      });
    });
  }

  group('NUL at the service level', () {
    test('one unsavable copy does not block every later copy', () {
      // Bug repro (BUG-1, effect): the NUL text can never be written, so it
      // sits in the waiting list; waiting items are saved before newer ones,
      // so nothing copied afterwards is ever saved until it is deleted.
      final dir = Directory.systemTemp.createTempSync('kusunga_nul_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = SqliteHistoryStore.open(
        path: '${dir.path}/k.db',
        keyHex: _key,
      );
      final source = FakeClipboardSource();
      var now = 0;
      final service = HistoryService(
        store: store,
        source: source,
        log: FakeLog(),
        clock: () => now += 10,
        writeClipboard: (_) async {},
      )..start();
      addTearDown(() {
        service.dispose();
        store.close();
      });

      source.copy('\u0000oops');
      source.copy('a normal copy');
      source.copy('another');

      expect(store.count, 3, reason: 'all three should be saved');
      expect(service.banners, isNot(contains(HistoryBanner.writeError)));
    });
  });
}

String _show(String s) => s.length > 60
    ? '${s.substring(0, 60)}... (${s.length} units)'
    : s.runes
          .map(
            (r) => r < 0x20 || r > 0x7e
                ? '\\u{${r.toRadixString(16)}}'
                : String.fromCharCode(r),
          )
          .join();
