import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/snippets/snippet.dart';

void main() {
  group('normaliseName', () {
    test('line breaks become one space and the ends are trimmed', () {
      expect(normaliseName('  My\nmobile '), 'My mobile');
      expect(normaliseName('a\r\n\r\nb'), 'a b');
      expect(normaliseName('a\u2028b\u2029c'), 'a b c');
    });

    test('NUL is removed (a name is a label, never pasted)', () {
      expect(normaliseName('\u0000Work'), 'Work');
    });
  });

  group('checkSnippet', () {
    test('a good snippet has no problems', () {
      expect(checkSnippet('My mobile', '07700 900123'), isEmpty);
    });

    test('empty name and empty content', () {
      expect(checkSnippet('', ''), {
        SnippetProblem.emptyName,
        SnippetProblem.emptyContent,
      });
      expect(checkSnippet(' \n ', ' \n\t'), {
        SnippetProblem.emptyName,
        SnippetProblem.emptyContent,
      });
    });

    test(
      'a name of only white space or invisible characters is empty (R3)',
      () {
        for (final blank in [
          '   ',
          '\t\u00A0\u3000',
          '\u200B\u200C\u200D',
          '\u2060\uFEFF',
          '\u202E\u202D\u2066\u2069',
          '\u200E\u200F\u061C',
          '\u00AD\u034F\u180E',
          '\u{E0041}\u{E0042}', // tag characters
          '\u0001\u007F\u0085',
          ' \u200B \u2060 ',
        ]) {
          expect(
            checkSnippet(blank, 'x'),
            {SnippetProblem.emptyName},
            reason: blank.runes.map((r) => r.toRadixString(16)).join(' '),
          );
        }
        // A visible letter among them is a name.
        expect(checkSnippet('\u200Ba\u200B', 'x'), isEmpty);
        expect(checkSnippet('🙂', 'x'), isEmpty);
      },
    );

    test('names over 100 characters, counted as characters', () {
      expect(checkSnippet('n' * 100, 'x'), isEmpty);
      expect(checkSnippet('n' * 101, 'x'), {SnippetProblem.longName});
      expect(checkSnippet('🙂' * 100, 'x'), isEmpty);
    });

    test('content over 1 MiB of UTF-8', () {
      expect(checkSnippet('n', 'a' * ClipItem.maxContentLength), isEmpty);
      expect(checkSnippet('n', 'é' * (ClipItem.maxContentLength ~/ 2 + 1)), {
        SnippetProblem.longContent,
      });
    });
  });

  group('suggestType', () {
    test('links reuse the history classifier', () {
      expect(suggestType('https://zoom.us/j/12345'), SnippetType.link);
      expect(suggestType('  http://example.com  '), SnippetType.link);
      expect(suggestType('ftp://example.com'), SnippetType.other);
    });

    test('one email address', () {
      expect(suggestType('will@example.com'), SnippetType.email);
      expect(
        suggestType(' first.last+tag@mail.example.co.uk\n'),
        SnippetType.email,
      );
      expect(suggestType('a@b'), SnippetType.other);
      expect(suggestType('mail will@example.com'), SnippetType.other);
      expect(suggestType('a@@example.com'), SnippetType.other);
    });

    test('one phone number', () {
      expect(suggestType('07700 900123'), SnippetType.phone);
      expect(suggestType('+44 7700 900123'), SnippetType.phone);
      expect(suggestType('(020) 7946-0018'), SnippetType.phone);
      expect(suggestType('+1.555.010.9999'), SnippetType.phone);
      expect(suggestType('123456'), SnippetType.other); // too short
      expect(suggestType('1234567890123456'), SnippetType.other); // too long
      expect(suggestType('2026-11-04'), SnippetType.other); // a date
      expect(suggestType('GB29 NWBK 6016 1331 9268 19'), SnippetType.other);
    });

    test('anything else is Other; an address is never guessed', () {
      expect(suggestType('1 High Street, London'), SnippetType.other);
      expect(suggestType(''), SnippetType.other);
    });
  });

  test('pin name skips lines that only look blank (F2)', () {
    expect(pinName('\u200B\u2060\nReal name\nmore'), 'Real name');
    expect(pinName(' \u00A0\uFEFF \n\u202E\nSecond'), 'Second');
    expect(pinName('\u200B\n\u2060'), '');
  });

  test('pin name: first line, cut to 40 characters', () {
    expect(pinName('Hello\nworld'), 'Hello');
    expect(pinName('\n\n  second line first  \nthird'), 'second line first');
    expect(pinName('x' * 60), 'x' * 40);
    expect(pinName('🙂' * 50), '🙂' * 40);
    expect(pinName('   '), '');
  });

  test('type labels are the words in the UI spec', () {
    expect(SnippetType.values.map((t) => t.label), [
      'Phone',
      'Email',
      'Link',
      'Address',
      'Other',
    ]);
    expect(SnippetType.values.map((t) => t.name), [
      'phone',
      'email',
      'link',
      'address',
      'other',
    ]);
  });
}
