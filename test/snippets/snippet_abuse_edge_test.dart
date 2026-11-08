// Tester probes for the abuse cases of the M1.4 design note ("Trust
// boundaries and abuse cases"): odd and huge text through the service into
// the encrypted file, markup in a name, and a foreign app that sets Kusunga's
// own marker. The native half (change numbers) has its own XCTest and C++
// checks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart' show OneLine;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late SqliteHistoryStore history;
  late SnippetStore store;
  late SnippetService service;
  late FakeLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_snip_abuse_');
    history = SqliteHistoryStore.open(
      path: '${dir.path}/kusunga.db',
      keyHex: _key,
    );
    store = history.snippetStore();
    log = FakeLog();
    service = SnippetService(
      store: store,
      log: log,
      editable: true,
      writeClipboard: (_) async => true,
    );
  });
  tearDown(() {
    service.dispose();
    history.close();
    dir.deleteSync(recursive: true);
  });

  SnippetSaveResult save(String name, String content) =>
      service.save(name: name, content: content, type: SnippetType.other);

  group('odd text in content comes back exactly', () {
    final cases = <String, String>{
      'NUL in the middle': 'before\u0000after',
      'NUL first and last': '\u0000text\u0000',
      'only a NUL': '\u0000',
      'RTL override and isolates':
          'abc \u{202E}123\u{202C} \u{2067}x\u{2069} \u{200F}',
      'zero width space, joiner, BOM': 'a\u{200B}b\u{200D}c\u{FEFF}d\u{2060}e',
      'emoji, ZWJ family, flag, skin tone':
          '\u{1F600} \u{1F469}\u{200D}\u{1F4BB} \u{1F1EC}\u{1F1E7} \u{1F44D}\u{1F3FD}',
      'combining marks': 'é̂̃ ä',
      'CJK and Arabic': '日本語 مرحبا',
      'line separators and CR LF': 'a\u{2028}b\u{2029}c\r\nd\re\n',
      'control characters': 'bell\u0007 esc\u001B del\u007F',
      'markup and script': '<script>alert(1)</script> <b>bold</b> &amp; \${x}',
      'SQL-looking': "'); DROP TABLE snippets; --",
      'leading and trailing spaces': '   padded   ',
    };
    for (final c in cases.entries) {
      test(c.key, () {
        final r = save('Name', c.value);
        expect(r.outcome, SnippetSave.saved);
        expect(store.contentOf(r.id!), c.value);
        // The list shows a preview without losing anything it can show.
        expect(service.items.single.preview, previewOf(c.value));
        expect(store.count, 1);
      });
    }
  });

  group('size limits are in UTF-8 bytes, on the file too', () {
    test('exactly 1 MiB of ASCII is kept; one byte more is refused', () {
      final ok = 'a' * ClipItem.maxContentLength;
      final r = save('Big', ok);
      expect(r.outcome, SnippetSave.saved);
      expect(store.contentOf(r.id!)!.length, ClipItem.maxContentLength);
      final over = save('Bigger', '${'a' * ClipItem.maxContentLength}a');
      expect(over.outcome, SnippetSave.invalid);
      expect(over.problems, {SnippetProblem.longContent});
      expect(store.count, 1);
    });

    test('1 MiB made of 3-byte and 4-byte characters counts bytes, not '
        'characters', () {
      // 349,525 euro signs are 1,048,575 bytes: one byte under the cap.
      final euros = '€' * 349525;
      expect(save('Euros', euros).outcome, SnippetSave.saved);
      // One more ASCII letter makes exactly 1 MiB: still fine.
      expect(save('Euros+1', '${euros}a').outcome, SnippetSave.saved);
      // One more euro sign is over.
      expect(save('Euros+€', '$euros€').outcome, SnippetSave.invalid);
      // 262,144 emoji (4 bytes each) are exactly 1 MiB.
      final emoji = '\u{1F600}' * 262144;
      expect(save('Emoji', emoji).outcome, SnippetSave.saved);
      expect(save('Emoji+1', '$emoji\u{1F600}').outcome, SnippetSave.invalid);
      expect(store.count, 3);
    });

    test('a huge snippet does not slow the list or the type suggestion', () {
      final r = save('Big', 'x' * ClipItem.maxContentLength);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        store.list();
      }
      suggestType('a@' * 500000);
      suggestType('+${'1' * 1000000}');
      suggestType('1 ' * 500000);
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(store.contentOf(r.id!)!.length, ClipItem.maxContentLength);
    });

    test('content of only white space and zero width marks', () {
      expect(save('N', '  \n\t ').problems, {SnippetProblem.emptyContent});
      // Zero width characters are not white space: it is content the user
      // chose, and it is kept as typed.
      expect(save('N', '\u{200B}').outcome, SnippetSave.saved);
    });
  });

  group('names', () {
    test('100 characters fit, 101 do not (ASCII)', () {
      expect(save('n' * 100, 'c').outcome, SnippetSave.saved);
      final r = save('n' * 101, 'c');
      expect(r.outcome, SnippetSave.invalid);
      expect(r.problems, {SnippetProblem.longName});
    });

    test('characters are counted as the file counts them: 100 emoji fit '
        '(200 UTF-16 units), 101 do not', () {
      final hundred = '\u{1F600}' * 100;
      final r = save(hundred, 'c');
      expect(r.outcome, SnippetSave.saved);
      expect(service.items.single.name, hundred);
      expect(save('$hundred\u{1F600}', 'c').problems, {
        SnippetProblem.longName,
      });
    });

    test('a name that is 100 characters only after the ends are trimmed '
        'and the line breaks are made one space', () {
      expect(save('  ${'a' * 100}  \n', 'c').outcome, SnippetSave.saved);
      // 50 + a break that becomes one space + 49 = 100 characters.
      expect(
        save('${'a' * 50}\r\n\r\n${'b' * 49}', 'c').outcome,
        SnippetSave.saved,
      );
      expect(
        service.items.last.name,
        '${'a' * 50} ${'b' * 49}',
        reason: 'one space for any run of line breaks',
      );
    });

    test('every kind of line break is gone from a saved name', () {
      for (final raw in [
        'a\nb',
        'a\r\nb',
        'a\rb',
        'a\u{2028}b',
        'a\u{2029}b',
        '\na\n',
        'a\n\n\n\nb',
      ]) {
        final r = save(raw, 'c');
        expect(r.outcome, SnippetSave.saved, reason: raw);
        final name = service.items.last.name;
        expect(name.contains(RegExp('[\r\n\u{2028}\u{2029}]')), isFalse);
        expect(name.trim(), name);
      }
    });

    test('NUL is removed from a name; a name of only NULs is empty', () {
      expect(save('a\u0000b', 'c').outcome, SnippetSave.saved);
      expect(service.items.single.name, 'ab');
      expect(save('\u0000\u0000', 'c').problems, {SnippetProblem.emptyName});
    });

    test('markup in a name is data: stored as typed, shown as text', () {
      const markup = '<b>Bold</b> <img src=x onerror=alert(1)> &lt;';
      final r = save(markup, 'c');
      expect(r.outcome, SnippetSave.saved);
      expect(service.items.single.name, markup);
      expect(OneLine.of(service.items.single.name), markup);
    });

    test('RTL marks and zero width characters in a name are never invisible '
        'on screen: the one-line form shows them as codes', () {
      for (final raw in [
        '\u{202E}nimdA',
        'Pay\u{200B}pal',
        '\u{200B}',
        '\u{200B}\u{200B}\u{200B}',
        '\u{FEFF}',
        'a\u{2066}b\u{2069}',
      ]) {
        final r = save(raw, 'c');
        // Whether such a name is accepted is the design's call (it is only a
        // label); what matters is that it is never blank or hidden in a row.
        if (r.outcome != SnippetSave.saved) continue;
        final shown = OneLine.of(service.items.last.name);
        expect(shown.trim(), isNotEmpty, reason: raw.codeUnits.toString());
        expect(
          shown.runes.where((r) => r >= 0x200B && r <= 0x200F),
          isEmpty,
          reason: 'hidden characters are made visible: $shown',
        );
        expect(shown.contains('\u{202E}'), isFalse);
      }
    });

    test('a long name with emoji and combining marks does not split a '
        'character when cut for a pinned history item', () {
      final text = '${'\u{1F469}\u{200D}\u{1F4BB}' * 30}\nsecond line';
      final name = pinName(text);
      expect(name.runes.length, lessThanOrEqualTo(pinNameLength));
      expect(
        String.fromCharCodes(name.runes),
        name,
        reason: 'valid UTF-16, no half emoji',
      );
    });

    test(
      'a pinned item with no usable first line gets an empty '
      'suggestion (so the editor asks for a name), and blank lines are skipped',
      () {
        expect(pinName('\n\n   \n'), '');
        expect(pinName('\n  hello  \nworld'), 'hello');
      },
    );
  });

  group('a foreign app sets Kusunga\'s own marker (abuse case 1)', () {
    late FakeClipboardSource source;
    late HistoryService hs;

    setUp(() {
      source = FakeClipboardSource();
      hs = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: log,
        snippetStore: MemorySnippetStore(),
      )..start();
    });
    tearDown(() => hs.dispose());

    test('text with the marker that is not in history is saved like any '
        'copy, even if it is the text of a snippet', () {
      hs.snippets.save(
        name: 'Home',
        content: '1 High Street, London',
        type: SnippetType.address,
      );
      source.controller.add(
        const ClipboardText('1 High Street, London', ownMarker: true),
      );
      expect(hs.items.map((i) => i.preview), ['1 High Street, London']);
      source.controller.add(
        const ClipboardText('totally different', ownMarker: true),
      );
      expect(hs.items.length, 2);
    });

    test('a plain copy of a snippet text is history as usual; nothing in '
        'history turns into a snippet by itself', () {
      hs.snippets.save(name: 'Mine', content: 'abc', type: SnippetType.other);
      source.copy('abc');
      source.copy('xyz');
      expect(hs.items.length, 2);
      expect(hs.snippets.items.map((s) => s.name), ['Mine']);
    });

    test('Copy of a snippet goes through the own-change writer only; no '
        'history item is made by Dart', () async {
      final id = hs.snippets
          .save(name: 'Mine', content: 'abc', type: SnippetType.other)
          .id!;
      expect(await hs.snippets.copy(id), isTrue);
      expect(source.ownWrites, ['abc']);
      expect(hs.items, isEmpty);
    });

    test('a failed own write (the native side says no) copies nothing and '
        'adds nothing to history', () async {
      source.writeOwnAnswer = false;
      final id = hs.snippets
          .save(name: 'Mine', content: 'abc', type: SnippetType.other)
          .id!;
      expect(await hs.snippets.copy(id), isFalse);
      expect(hs.items, isEmpty);
    });
  });
}
