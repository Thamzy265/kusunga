// The snippet service and typed shortcuts (M1.5): save with a shortcut, the
// live check the editor runs as the user types, and the clash the store finds
// in the save transaction.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_shortcut.dart';

import '../support/fakes.dart';

void main() {
  late MemorySnippetStore store;
  late FakeLog log;

  SnippetService make({bool editable = true}) => SnippetService(
    store: store,
    log: log,
    editable: editable,
    writeClipboard: (_) async => true,
  );

  setUp(() {
    store = MemorySnippetStore();
    log = FakeLog();
  });

  test('save keeps the shortcut; an empty one is none', () {
    final s = make();
    final a = s.save(
      name: 'Work email',
      content: 'will@example.com',
      type: SnippetType.email,
      shortcut: ';email',
    );
    expect(a.outcome, SnippetSave.saved);
    final b = s.save(
      name: 'Mobile',
      content: '07700 900123',
      type: SnippetType.phone,
      shortcut: '',
    );
    expect(b.outcome, SnippetSave.saved);
    expect(s.items.map((i) => i.shortcut), [';email', null]);
  });

  test('a bad shortcut is reported with the other problems, nothing saved', () {
    final s = make();
    final r = s.save(
      name: '',
      content: 'x',
      type: SnippetType.other,
      shortcut: '; e',
    );
    expect(r.outcome, SnippetSave.invalid);
    expect(r.problems, {
      SnippetProblem.emptyName,
      SnippetProblem.shortcutSpaces,
    });
    final r2 = s.save(
      name: 'n',
      content: 'x',
      type: SnippetType.other,
      shortcut: ';',
    );
    expect(r2.problems, {SnippetProblem.shortcutLength});
    expect(s.items, isEmpty);
  });

  test('a clash is reported with the other snippet; nothing is saved', () {
    final s = make();
    s.save(
      name: 'Work email',
      content: 'x',
      type: SnippetType.email,
      shortcut: ';email',
    );
    final r = s.save(
      name: 'Short',
      content: 'y',
      type: SnippetType.other,
      shortcut: ';em',
    );
    expect(r.outcome, SnippetSave.shortcutTaken);
    expect(r.clash!.kind, ShortcutClashKind.newIsStart);
    expect(r.clash!.otherName, 'Work email');
    expect(s.items.length, 1);
    // Codes only: nothing about the clash is logged.
    expect(log.codes, isEmpty);
  });

  test('a clash found only by the store (the list was out of date) is '
      'reported the same way', () {
    final s = make();
    // Another save straight into the store, which the service has not seen.
    store.insert(
      name: 'Behind',
      content: 'x',
      type: SnippetType.other,
      nowMs: 1,
      shortcut: ';mob',
    );
    expect(s.shortcutIssue(';mob'), isNull, reason: 'not in the list yet');
    final r = s.save(
      name: 'Mine',
      content: 'y',
      type: SnippetType.other,
      shortcut: ';mob',
    );
    expect(r.outcome, SnippetSave.shortcutTaken);
    expect(r.clash!.otherName, 'Behind');
  });

  test(
    'the live check: text problems first, then clashes; own shortcut OK',
    () {
      final s = make();
      final id = s
          .save(
            name: 'Work email',
            content: 'x',
            type: SnippetType.email,
            shortcut: ';email',
          )
          .id!;
      expect(s.shortcutIssue(''), isNull);
      expect(
        s.shortcutIssue(';'),
        ShortcutIssue.problem(ShortcutProblem.length),
      );
      expect(
        s.shortcutIssue('; x'),
        ShortcutIssue.problem(ShortcutProblem.spaces),
      );
      expect(
        s.shortcutIssue(';emailx')!.clash!.kind,
        ShortcutClashKind.otherIsStart,
      );
      expect(s.shortcutIssue(';email', selfId: id), isNull);
      expect(s.shortcutIssue(';addr'), isNull);
    },
  );

  test('the shortcut table has only snippets with a shortcut', () {
    final s = make();
    final a = s
        .save(name: 'A', content: 'a', type: SnippetType.other, shortcut: ';a1')
        .id!;
    s.save(name: 'B', content: 'b', type: SnippetType.other);
    expect(s.shortcutTable, [(id: a, shortcut: ';a1')]);
  });
}
