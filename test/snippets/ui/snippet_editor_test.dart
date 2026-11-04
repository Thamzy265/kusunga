import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/snippet_store.dart';
import 'package:kusunga/snippets/ui/snippet_editor.dart';
import 'package:kusunga/theme/tokens.dart';

import '../qa_support.dart';
import '../../support/fakes.dart';

void main() {
  late ContentReadFailsStore store;
  late SnippetService service;
  late FakeLog log;
  int? result;
  var closed = false;

  setUp(() {
    store = ContentReadFailsStore();
    log = FakeLog();
    service = SnippetService(
      store: store,
      log: log,
      editable: true,
      writeClipboard: (_) async => true,
    );
    result = null;
    closed = false;
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
                onPressed: () async {
                  result = await showSnippetEditor(
                    context,
                    service: service,
                    start: start,
                  );
                  closed = true;
                },
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

  Finder field(String id) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.identifier == id,
    ),
    matching: find.byType(TextField),
  );

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  FocusNode? focusOf(WidgetTester tester, String id) =>
      tester.widget<TextField>(field(id)).focusNode;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(hook('snippet-editor-save'));
    await tester.pumpAndSettle();
  }

  testWidgets('new: title, labels, note, focus in Name, Tab order', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    expect(find.text('New snippet'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(
      find.text(
        'For bank or card details, wait for the secure vault in a later '
        'update.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    final name = tester.widget<TextField>(field('snippet-editor-name'));
    expect(name.focusNode!.hasFocus, isTrue);
    expect(name.maxLines, 1);
    // The dialog is named after its title.
    expect(
      tester.widget<Semantics>(hook('snippet-editor')).properties.label,
      'New snippet',
    );
  });

  testWidgets('the type is suggested from the content, and the user wins', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-content'), 'will@example.com');
    await tester.pump();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('(suggested)'), findsOneWidget);
    await tester.tap(hook('snippet-editor-type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Address').last);
    await tester.pumpAndSettle();
    expect(find.text('(suggested)'), findsNothing);
    await tester.enterText(field('snippet-editor-content'), '07700 900123');
    await tester.pump();
    expect(find.text('Address'), findsOneWidget, reason: 'the choice stays');
  });

  testWidgets('Save creates the snippet with a one-line name and closes', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), 'My mobile');
    await tester.enterText(field('snippet-editor-content'), '07700 900123');
    await save(tester);
    expect(closed, isTrue);
    expect(result, isNotNull);
    final s = service.items.single;
    expect(s.name, 'My mobile');
    expect(s.type, SnippetType.phone);
    expect(service.textOf(s.id), '07700 900123');
  });

  testWidgets('a name with line breaks becomes one line (newlines removed)', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), 'My\nmobile');
    expect(
      tester.widget<TextField>(field('snippet-editor-name')).controller!.text,
      'Mymobile',
    );
  });

  testWidgets('Cmd+Enter saves (Ctrl+Enter on Windows)', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), 'A');
    await tester.enterText(field('snippet-editor-content'), 'a');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(service.items.single.name, 'A');
  });

  testWidgets('Ctrl+Enter saves too', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), 'A');
    await tester.enterText(field('snippet-editor-content'), 'a');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('empty fields: an error under each, focus to the first bad one, '
      'Save stays enabled', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await save(tester);
    expect(closed, isFalse);
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(find.text('Enter the text to paste.'), findsOneWidget);
    expect(focusOf(tester, 'snippet-editor-name')!.hasFocus, isTrue);
    final saveButton = tester.widget<FilledButton>(
      find.descendant(
        of: hook('snippet-editor-save'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.enterText(field('snippet-editor-name'), 'Name');
    await save(tester);
    expect(find.text('Enter a name.'), findsNothing);
    expect(focusOf(tester, 'snippet-editor-content')!.hasFocus, isTrue);
  });

  testWidgets('a long name and content say why', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), 'n' * 101);
    await tester.enterText(
      field('snippet-editor-content'),
      // Just over 1 MiB, in words and lines (a single 1 MiB word is very
      // slow to lay out in a test).
      '${'word word word word word word word word word word word\n' * 19100}xx',
    );
    await save(tester);
    expect(find.text('Names can be up to 100 characters.'), findsOneWidget);
    expect(
      find.text("That's too long. Snippets can be up to 1 MB."),
      findsOneWidget,
    );
    expect(service.items, isEmpty);
  });

  testWidgets("each error is the field's own error text (linked to it)", (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await save(tester);
    expect(
      tester
          .widget<TextField>(field('snippet-editor-name'))
          .decoration!
          .errorText,
      'Enter a name.',
    );
    expect(
      tester
          .widget<TextField>(field('snippet-editor-content'))
          .decoration!
          .errorText,
      'Enter the text to paste.',
    );
  });

  testWidgets('a failed save keeps the text and shows the banner', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    store.failWrites = true;
    await tester.enterText(field('snippet-editor-name'), 'Kept name');
    await tester.enterText(field('snippet-editor-content'), 'kept text');
    await save(tester);
    expect(closed, isFalse);
    expect(find.text("Couldn't save the snippet. Try again."), findsOneWidget);
    expect(find.text('Kept name'), findsOneWidget);
    expect(find.text('kept text'), findsOneWidget);
    store.failWrites = false;
    await save(tester);
    expect(closed, isTrue);
  });

  testWidgets('at the cap the editor says so', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    store.capped = true;
    await tester.enterText(field('snippet-editor-name'), 'A');
    await tester.enterText(field('snippet-editor-content'), 'a');
    await save(tester);
    expect(
      find.text(
        'You have 1,000 snippets, the most Kusunga keeps. Delete one to add '
        'another.',
      ),
      findsOneWidget,
    );
    expect(closed, isFalse);
  });

  testWidgets('Esc with no changes closes at once', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('Cancel with changes asks; Keep editing keeps the text', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), 'Draft');
    await tester.tap(hook('snippet-editor-cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(
      find.text("Your changes to this snippet won't be saved."),
      findsOneWidget,
    );
    // Focus is on Keep editing.
    final keep = find.widgetWithText(TextButton, 'Keep editing');
    expect(
      Focus.of(tester.element(find.text('Keep editing'))).hasFocus,
      isTrue,
    );
    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('Esc with changes asks; Discard closes without saving', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-content'), 'draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(service.items, isEmpty);
  });

  testWidgets('edit: title, fields filled, Save changes that snippet', (
    tester,
  ) async {
    final id = service
        .save(
          name: 'Work email',
          content: 'a@example.com',
          type: SnippetType.email,
        )
        .id!;
    await open(tester, SnippetEditorStart.edit(service.items.single));
    expect(find.text('Edit snippet'), findsOneWidget);
    expect(find.text('Work email'), findsOneWidget);
    expect(find.text('a@example.com'), findsOneWidget);
    expect(find.text('(suggested)'), findsNothing);
    await tester.enterText(field('snippet-editor-content'), 'b@example.com');
    await save(tester);
    expect(result, id);
    expect(service.textOf(id), 'b@example.com');
    expect(service.items.length, 1);
  });

  testWidgets('from history: first line as the name, full text, suggested '
      'type, focus in Content', (tester) async {
    final text = 'https://zoom.us/j/12345\nsecond line';
    await open(tester, SnippetEditorStart.fromHistory(text));
    expect(find.text('New snippet'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('snippet-editor-name')).controller!.text,
      'https://zoom.us/j/12345',
    );
    expect(
      tester
          .widget<TextField>(field('snippet-editor-content'))
          .controller!
          .text,
      text,
    );
    expect(focusOf(tester, 'snippet-editor-content')!.hasFocus, isTrue);
    // Two lines are not one link: Other, suggested.
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('(suggested)'), findsOneWidget);
    // Nothing typed yet: Esc closes without asking.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('a name from history is cut to 40 characters', (tester) async {
    await open(tester, SnippetEditorStart.fromHistory('x' * 80));
    expect(
      tester.widget<TextField>(field('snippet-editor-name')).controller!.text,
      'x' * 40,
    );
  });

  testWidgets('under 600 px the editor fills the window, with no overflow', (
    tester,
  ) async {
    await open(
      tester,
      const SnippetEditorStart.create(),
      size: const Size(360, 400),
    );
    expect(find.byType(Dialog), findsOneWidget);
    final dialog = tester.getSize(find.byType(Dialog));
    expect(dialog.width, 360);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 600 px and wider the editor is a 480 px sheet', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    final sheet = tester.getSize(
      find.byKey(const ValueKey('snippet-editor-sheet')),
    );
    expect(sheet.width, 480);
  });

  testWidgets('200% text at the smallest window has no overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(
      tester,
      const SnippetEditorStart.create(),
      size: const Size(360, 400),
    );
    await save(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content grows to 8 lines, then scrolls inside', (tester) async {
    await open(tester, const SnippetEditorStart.create());
    final content = tester.widget<TextField>(field('snippet-editor-content'));
    expect(content.maxLines, 8);
  });

  testWidgets('no name or content in the log, even when saving fails', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    store.failWrites = true;
    await tester.enterText(field('snippet-editor-name'), 'Secret');
    await tester.enterText(field('snippet-editor-content'), 'secret');
    await save(tester);
    expect(log.codes, [LogCode.snippetSaveFailed]);
    expect(SnippetStore.maxCount, 1000);
  });

  group('the whole text cannot be read (TB-2)', () {
    late int id;
    final long = '${'y' * 2999}END';

    setUp(() {
      id = service
          .save(name: 'Long', content: long, type: SnippetType.other)
          .id!;
      store.failContentReads = true;
    });

    testWidgets('Edit opens read-only: the banner says so, the content '
        'cannot be changed, and Save changes nothing', (tester) async {
      await open(tester, SnippetEditorStart.edit(service.items.single));
      expect(
        find.text("Couldn't open the snippet. Try again."),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(field('snippet-editor-content')).readOnly,
        isTrue,
      );
      expect(log.codes, contains(LogCode.snippetOpenFailed));
      await tester.enterText(field('snippet-editor-name'), 'Renamed');
      await save(tester);
      expect(closed, isFalse);
      store.failContentReads = false;
      expect(store.contentOf(id), long);
      expect(store.list().single.name, 'Long');
    });

    testWidgets('once the text can be read again, Save keeps it whole', (
      tester,
    ) async {
      await open(tester, SnippetEditorStart.edit(service.items.single));
      await tester.enterText(field('snippet-editor-name'), 'Renamed');
      store.failContentReads = false;
      await save(tester);
      expect(closed, isTrue);
      expect(store.contentOf(id), long);
      expect(store.list().single.name, 'Renamed');
    });
  });

  group('pasting into Name (R2)', () {
    void mockClipboard(WidgetTester tester, String text) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
          'Clipboard.getData' => {'text': text},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    String nameText(WidgetTester tester) =>
        tester.widget<TextField>(field('snippet-editor-name')).controller!.text;

    testWidgets(
      'the paste key turns line breaks into spaces',
      (tester) async {
        final mac = defaultTargetPlatform == TargetPlatform.macOS;
        mockClipboard(tester, 'Line one\nLine two\r\nLine\u2028three');
        await open(tester, const SnippetEditorStart.create());
        final modifier = mac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(nameText(tester), 'Line one Line two Line three');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'Ctrl+V on Windows does the same',
      (tester) async {
        mockClipboard(tester, 'Line one\nLine two');
        await open(tester, const SnippetEditorStart.create());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(nameText(tester), 'Line one Line two');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'the Paste item of the right-click menu does the same',
      (tester) async {
        mockClipboard(tester, 'Line one\nLine two');
        await open(tester, const SnippetEditorStart.create());
        await tester.tap(
          field('snippet-editor-name'),
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste'));
        await tester.pumpAndSettle();
        expect(nameText(tester), 'Line one Line two');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'the paste goes where the caret is and replaces a selection',
      (tester) async {
        mockClipboard(tester, 'mid\ndle');
        await open(tester, const SnippetEditorStart.create());
        await tester.enterText(field('snippet-editor-name'), 'start end');
        final c = tester
            .widget<TextField>(field('snippet-editor-name'))
            .controller!;
        c.selection = const TextSelection(baseOffset: 6, extentOffset: 9);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(c.text, 'start mid dle');
        expect(c.selection, const TextSelection.collapsed(offset: 13));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'Content keeps its line breaks',
      (tester) async {
        mockClipboard(tester, 'Line one\nLine two');
        await open(tester, const SnippetEditorStart.create());
        await tester.tap(field('snippet-editor-content'));
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(field('snippet-editor-content'))
              .controller!
              .text,
          'Line one\nLine two',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  testWidgets('a name of only invisible characters gets "Enter a name." (R3)', (
    tester,
  ) async {
    await open(tester, const SnippetEditorStart.create());
    await tester.enterText(field('snippet-editor-name'), '\u200B \u2060\uFEFF');
    await tester.enterText(field('snippet-editor-content'), 'text');
    await save(tester);
    expect(closed, isFalse);
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(store.list(), isEmpty);
  });
}
