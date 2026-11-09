import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/snippet_shortcut.dart';

void main() {
  group('shortcut text (design note, "Shortcut rules")', () {
    test('2 to 32 characters, counted as code points', () {
      expect(checkShortcutText(';e'), isNull);
      expect(checkShortcutText(';' * 32), isNull);
      expect(checkShortcutText(';'), ShortcutProblem.length);
      expect(checkShortcutText(';' * 33), ShortcutProblem.length);
      // Two emoji are 4 UTF-16 units but 2 characters.
      expect(checkShortcutText('😀😀'), isNull);
      expect(checkShortcutText('😀' * 32), isNull);
      expect(checkShortcutText('😀' * 33), ShortcutProblem.length);
    });

    test('no spaces, tabs, line breaks or control characters', () {
      for (final bad in [
        '; email',
        ';email ',
        ' ;email',
        ';e\tmail',
        ';e\nmail',
        ';e\rmail',
        ';e mail',
        ';e mail',
        ';e\u0000mail',
        ';e　mail',
      ]) {
        expect(checkShortcutText(bad), ShortcutProblem.spaces, reason: bad);
      }
    });

    test('the spaces problem wins over the length problem', () {
      expect(checkShortcutText(' '), ShortcutProblem.spaces);
    });

    test('an empty field is no shortcut', () {
      expect(shortcutOrNull(''), isNull);
      expect(shortcutOrNull(null), isNull);
      expect(shortcutOrNull(';e'), ';e');
    });

    test('the store check refuses bad text without echoing it', () {
      checkShortcutField(null);
      checkShortcutField(';email');
      expect(
        () => checkShortcutField(';my secret'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'text',
            isNot(contains('secret')),
          ),
        ),
      );
    });
  });

  group('clashes (PM decision D1 A)', () {
    const others = <ShortcutOwner>[
      (id: 1, name: 'Work email', shortcut: ';email'),
      (id: 2, name: 'My mobile', shortcut: ';mob'),
    ];

    test('the same shortcut', () {
      final c = findShortcutClash(';email', others)!;
      expect(c.kind, ShortcutClashKind.same);
      expect(c.otherName, 'Work email');
      expect(c.otherShortcut, ';email');
      expect(c.otherId, 1);
    });

    test('another shortcut is the start of the new one', () {
      final c = findShortcutClash(';mobile', others)!;
      expect(c.kind, ShortcutClashKind.otherIsStart);
      expect(c.otherShortcut, ';mob');
    });

    test('the new shortcut is the start of another one', () {
      final c = findShortcutClash(';em', others)!;
      expect(c.kind, ShortcutClashKind.newIsStart);
      expect(c.otherShortcut, ';email');
    });

    test('case-sensitive: ;Email is not ;email', () {
      expect(findShortcutClash(';Email', others), isNull);
      expect(findShortcutClash(';EM', others), isNull);
    });

    test('a snippet never clashes with itself', () {
      expect(findShortcutClash(';email', others, selfId: 1), isNull);
      expect(findShortcutClash(';emailx', others, selfId: 1), isNull);
    });

    test('unrelated and suffix shortcuts are fine', () {
      expect(findShortcutClash(';addr', others), isNull);
      expect(findShortcutClash('x;email', others), isNull);
    });

    test('ShortcutTaken never shows the shortcut or the name', () {
      final e = ShortcutTaken(findShortcutClash(';email', others)!);
      expect(e.toString(), isNot(contains('email')));
      expect(e.toString(), isNot(contains('Work')));
    });
  });
}
