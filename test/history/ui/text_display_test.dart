import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/ui/text_display.dart';

void main() {
  group('visibleText', () {
    test('plain text, emoji and newlines pass through', () {
      expect(visibleText('Call me on 07700 900123'), 'Call me on 07700 900123');
      expect(visibleText('a\nb \u{1F600}'), 'a\nb \u{1F600}');
      expect(visibleText('a\r\nb'), 'a\nb');
    });

    test('control characters become visible pictures', () {
      expect(visibleText('a\u0000b'), 'a␀b');
      expect(visibleText('a\u001Bb'), 'a␛b');
      expect(visibleText('a\u007Fb'), 'a␡b');
      expect(visibleText('a\rb'), 'a␍b');
    });

    test('bidi overrides and invisible characters show their code point', () {
      expect(visibleText('a${String.fromCharCode(0x202E)}b'), 'a[U+202E]b');
      expect(
        visibleText(
          'a${String.fromCharCode(0x2066)}b${String.fromCharCode(0x2069)}',
        ),
        'a[U+2066]b[U+2069]',
      );
      expect(visibleText('a​b'), 'a[U+200B]b');
      expect(visibleText('a﻿b'), 'a[U+FEFF]b');
      expect(visibleText('a\u0085b'), 'a[U+0085]b');
    });

    test('text that pretends to be a different link stays readable', () {
      final sneaky =
          'https://example.com/${String.fromCharCode(0x202E)}fdp.exe';
      expect(visibleText(sneaky), contains('[U+202E]'));
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
    int ago(Duration d) => now - d.inMilliseconds;

    test('short form for the row', () {
      expect(relativeTimeShort(now, ago(const Duration(seconds: 20))), 'now');
      expect(relativeTimeShort(now, ago(const Duration(minutes: 2))), '2 min');
      expect(relativeTimeShort(now, ago(const Duration(hours: 1))), '1 h');
      expect(relativeTimeShort(now, ago(const Duration(days: 3))), '3 d');
    });

    test('long form for screen readers', () {
      expect(
        relativeTimeLong(now, ago(const Duration(seconds: 20))),
        'just now',
      );
      expect(
        relativeTimeLong(now, ago(const Duration(minutes: 1))),
        '1 minute ago',
      );
      expect(
        relativeTimeLong(now, ago(const Duration(minutes: 5))),
        '5 minutes ago',
      );
      expect(
        relativeTimeLong(now, ago(const Duration(hours: 1))),
        '1 hour ago',
      );
      expect(relativeTimeLong(now, ago(const Duration(days: 2))), '2 days ago');
    });

    test('a time in the future counts as now', () {
      expect(relativeTimeShort(now, now + 5000), 'now');
    });
  });
}
