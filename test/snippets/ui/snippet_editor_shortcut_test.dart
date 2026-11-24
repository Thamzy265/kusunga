// The editor's Shortcut field (M1.5 UI spec, "Editor Shortcut field" and
// "Copy").
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippet_editor.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';

void main() {
  late SnippetService service;
  int? result;

  setUp(() {
    service = SnippetService(
      store: MemorySnippetStore(),
      log: FakeLog(),
      editable: true,
      writeClipboard: (_) async => true,
    );
    result = null;
  });

  Future<void> open(
    WidgetTester tester,
    SnippetEditorStart start, {
    Size size = const Size(800, 632),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await showSnippetEditor(
                  context,
                  service: service,
                  start: start,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );
  Finder field(String id) =>
      find.descendant(of: hook(id), matching: find.byType(TextField));
  TextField shortcutField(WidgetTester tester) =>
      tester.widget<TextField>(field('snippet-editor-shortcut'));
  String? errorOf(WidgetTester tester) =>
      shortcutField(tester).decoration!.errorText;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(hook('snippet-editor-save'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String name = 'Work email',
    String content = 'will@example.com',
    required String shortcut,
  }) async {
    await tester.enterText(field('snippet-editor-name'), name);
    await tester.enterText(field('snippet-editor-content'), content);
    await tester.enterText(field('snippet-editor-shortcut'), shortcut);
  }

  void addOther(String name, String shortcut) => service.save(
    name: name,
    content: 'x',
    type: SnippetType.other,
    shortcut: shortcut,
  );

  testWidgets('label, hint and placeholder as in the spec; empty is fine', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    final d = shortcutField(tester).decoration!;
    expect(d.labelText, 'Shortcut (optional)');
    expect(d.hintText, ';email');
    expect(d.helperText, 'Type this in any app to paste.');
    await fill(tester, shortcut: '');
    await save(tester);
    expect(result, isNotNull);
    expect(service.items.single.shortcut, isNull);
  });

  testWidgets('Tab order: Name, Type, Shortcut, Content', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    FocusNode node(String id) => shortcutOrField(tester, id);
    expect(node('snippet-editor-name').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Type
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(node('snippet-editor-shortcut').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(node('snippet-editor-content').hasFocus, isTrue);
  });

  testWidgets('saves the shortcut and the row has it', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await fill(tester, shortcut: ';email');
    await save(tester);
    expect(result, isNotNull);
    expect(service.items.single.shortcut, ';email');
  });

  testWidgets('the field refuses more than 32 characters', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-shortcut'), ';' * 40);
    await tester.pump();
    expect(shortcutField(tester).controller!.text.length, 32);
  });

  testWidgets('checked 500 ms after typing stops, with the spec copy', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-shortcut'), ';');
    await tester.pump(const Duration(milliseconds: 400));
    expect(errorOf(tester), isNull, reason: 'not yet');
    await tester.pump(const Duration(milliseconds: 150));
    expect(errorOf(tester), 'Use 2 to 32 characters.');
    await tester.enterText(field('snippet-editor-shortcut'), '; e');
    await tester.pump(const Duration(milliseconds: 600));
    expect(errorOf(tester), "Shortcuts can't have spaces or line breaks.");
    await tester.enterText(field('snippet-editor-shortcut'), ';e');
    await tester.pump(const Duration(milliseconds: 600));
    expect(errorOf(tester), isNull);
  });

  testWidgets('the three clash messages name the other snippet', (
    tester,
  ) async {
    addOther('Work email', ';email');
    await open(tester, const SnippetEditorStart.create());
    Future<String?> check(String text) async {
      await tester.enterText(field('snippet-editor-shortcut'), text);
      await tester.pump(const Duration(milliseconds: 600));
      return errorOf(tester);
    }

    expect(
      await check(';email'),
      '“Work email” already uses ;email. Choose another shortcut.',
    );
    expect(
      await check(';emailx'),
      '“Work email” uses ;email, so ;emailx would never fire. Choose one '
      "that doesn't start with ;email.",
    );
    expect(
      await check(';em'),
      '“Work email” uses ;email, which starts with ;em, so ;email would stop '
      'firing. Choose a longer or different shortcut.',
    );
  });

  testWidgets('Save with a bad shortcut keeps the text, shows the error and '
      'moves focus to the field', (tester) async {
    addOther('Work email', ';email');
    await open(tester, const SnippetEditorStart.create());
    await fill(tester, name: 'Other', content: 'y', shortcut: ';em');
    await save(tester);
    expect(result, isNull);
    expect(
      errorOf(tester),
      startsWith('“Work email” uses ;email, which starts with ;em'),
    );
    expect(shortcutField(tester).focusNode!.hasFocus, isTrue);
    expect(shortcutField(tester).controller!.text, ';em');
    expect(service.items.length, 1);
  });

  testWidgets('C8: Save with an empty name keeps the live clash message', (
    tester,
  ) async {
    addOther('Work email', ';email');
    await open(tester, const SnippetEditorStart.create());
    await fill(tester, name: 'Other', content: 'y', shortcut: ';email');
    await tester.pump(const Duration(milliseconds: 600));
    const clash = '“Work email” already uses ;email. Choose another shortcut.';
    expect(errorOf(tester), clash);
    await tester.enterText(field('snippet-editor-name'), '');
    await save(tester);
    expect(result, isNull);
    expect(errorOf(tester), clash);
  });

  testWidgets('C8: Save at once after typing a clash shows it with the name '
      'error', (tester) async {
    addOther('Work email', ';email');
    await open(tester, const SnippetEditorStart.create());
    // Saved before the 500 ms check ran.
    await fill(tester, name: '', content: 'y', shortcut: ';emailx');
    await save(tester);
    expect(errorOf(tester), startsWith('“Work email” uses ;email, so ;emailx'));
  });

  testWidgets('a bad name and a bad shortcut: focus goes to the name first', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await fill(tester, name: '', shortcut: ';');
    await save(tester);
    expect(errorOf(tester), 'Use 2 to 32 characters.');
    expect(
      tester
          .widget<TextField>(field('snippet-editor-name'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('an all-letter shortcut shows the tip under the hint', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-shortcut'), 'email');
    await tester.pump();
    expect(
      shortcutField(tester).decoration!.helperText,
      'Type this in any app to paste.\nTip: start with a symbol like ; so '
      "normal typing doesn't trigger it.",
    );
    await tester.enterText(field('snippet-editor-shortcut'), ';email');
    await tester.pump();
    expect(
      shortcutField(tester).decoration!.helperText,
      'Type this in any app to paste.',
    );
  });

  testWidgets('edit shows the shortcut; keeping it is no clash; removing it '
      'saves none', (tester) async {
    addOther('Work email', ';email');
    await open(tester, SnippetEditorStart.edit(service.items.single));
    expect(shortcutField(tester).controller!.text, ';email');
    await tester.enterText(field('snippet-editor-name'), 'Renamed');
    await tester.pump(const Duration(milliseconds: 600));
    expect(errorOf(tester), isNull);
    await tester.enterText(field('snippet-editor-shortcut'), '');
    await save(tester);
    expect(service.items.single.shortcut, isNull);
    expect(service.items.single.name, 'Renamed');
  });

  testWidgets('a changed shortcut counts as a change for Esc', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-shortcut'), ';x');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
  });
}

FocusNode shortcutOrField(WidgetTester tester, String id) {
  if (id == 'snippet-editor-name' ||
      id == 'snippet-editor-shortcut' ||
      id == 'snippet-editor-content') {
    return tester
        .widget<TextField>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.identifier == id,
            ),
            matching: find.byType(TextField),
          ),
        )
        .focusNode!;
  }
  throw ArgumentError(id);
}
