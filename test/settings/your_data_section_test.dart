// M1.8 UI spec (docs/ui/your-data.md): the Your data section in Settings,
// the export, import and Delete everything dialogs, their states, copy,
// focus and breakpoints. Key deletion goes through a fake key store only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/settings/ui/your_data_section.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  late Directory dir;
  late FakeClipboardSource source;
  late FakeLog log;
  late FakeFilePort files;
  late FakeKeyStore keys;
  late HistoryService service;
  late int quits;
  late int afterImports;
  late List<String> steps;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_ydui_');
    source = FakeClipboardSource();
    log = FakeLog();
    files = FakeFilePort();
    keys = FakeKeyStore(stored: _key);
    quits = 0;
    afterImports = 0;
    steps = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryService sqliteService() {
    final store = SqliteHistoryStore.open(
      path: p.join(dir.path, 'kusunga.db'),
      keyHex: _key,
    );
    return HistoryService(
      store: store,
      source: source,
      log: log,
      snippetStore: store.snippetStore(),
      ignoredAppStore: store.ignoredAppStore(),
    )..start();
  }

  Future<void> show(
    WidgetTester tester, {
    HistoryService? history,
    Size size = const Size(800, 900),
    double textScale = 1,
    Duration keyTimeout = const Duration(seconds: 30),
    EraseTarget? target,
  }) async {
    service = history ?? sqliteService();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: SettingsScreen(
          service: service,
          onShowPrivacy: () {},
          yourData: YourDataSetup(
            files: files,
            log: log,
            eraser: () => DataEraser(
              target:
                  target ??
                  DefaultEraseTarget(keys: keys, folder: () async => dir),
              log: log,
              stopFileLog: () => steps.add('stopFileLog'),
              keyTimeout: keyTimeout,
            ),
            quit: () async => quits++,
            afterImport: () async => afterImports++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> tapHook(WidgetTester tester, String id) async {
    await tester.ensureVisible(hook(id));
    await tester.tap(hook(id));
    await tester.pump();
    await tester.pump();
  }

  bool focused(WidgetTester tester, String text) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    var found = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is ButtonStyleButton || e.widget is Checkbox) {
        found = find
            .descendant(of: find.byWidget(e.widget), matching: find.text(text))
            .evaluate()
            .isNotEmpty;
        return false;
      }
      return true;
    });
    if (!found && ctx.widget is Checkbox) return false;
    return found;
  }

  bool focusedCheckbox() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is Checkbox ||
            ctx.findAncestorWidgetOfExactType<Checkbox>() != null);
  }

  /// Lets work started inside runAsync (file reads) finish its
  /// continuations, then settles the frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// The live region (announced when it appears) around [finder].
  Finder liveRegionAround(Finder finder) => find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.liveRegion == true,
    ),
  );

  void seedHistory(int n) {
    for (var i = 0; i < n; i++) {
      source.copy('item $i');
    }
  }

  group('section', () {
    testWidgets('heading, four buttons and two help lines (copy)', (
      tester,
    ) async {
      await show(tester);
      final heading = tester.getSemantics(find.text('Your data'));
      expect(heading.flagsCollection.isHeader, isTrue);
      for (final label in [
        'Export…',
        'Import…',
        'Delete all history…',
        'Delete everything…',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.text(
          'Export saves your snippets, and history if you choose, to a file. '
          "The file isn't encrypted.",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Delete everything removes all Kusunga data from this computer, '
          'including its key.',
        ),
        findsOneWidget,
      );
      for (final id in [
        'your-data-export',
        'your-data-import',
        'your-data-delete-history',
        'your-data-delete-everything',
      ]) {
        expect(hook(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('Delete all history is disabled when history is empty', (
      tester,
    ) async {
      await show(tester);
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Delete all history…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      seedHistory(1);
      await tester.pump();
      final again = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Delete all history…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(again.onPressed, isNotNull);
    });

    testWidgets('memory-only: help adds "History isn\'t saved right now.", '
        'Import is disabled with its line (G2); the rest still works', (
      tester,
    ) async {
      await show(
        tester,
        history: HistoryService(
          store: MemoryHistoryStore(),
          source: source,
          log: log,
          notices: {HistoryNotice.memoryOnly},
        )..start(),
      );
      expect(find.text("History isn't saved right now."), findsOneWidget);
      expect(
        find.text(
          "Import isn't available right now, because history isn't being "
          'saved.',
        ),
        findsOneWidget,
      );
      final import = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Import…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(import.onPressed, isNull);
      final export = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Export…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(export.onPressed, isNotNull);
    });

    testWidgets('incompatible file: Import disabled with its line, no '
        'memory-only line', (tester) async {
      await show(
        tester,
        history: HistoryService(
          store: MemoryHistoryStore(),
          source: source,
          log: log,
          notices: {HistoryNotice.incompatible},
        )..start(),
      );
      expect(find.text("History isn't saved right now."), findsNothing);
      expect(
        find.text(
          "Import isn't available right now, because history isn't being "
          'saved.',
        ),
        findsOneWidget,
      );
    });

    for (final (width, scale, perRow) in [
      (320.0, 1.0, 1),
      (360.0, 2.0, 1),
      (480.0, 1.0, 2),
      (800.0, 1.0, 2),
    ]) {
      testWidgets('at $width px and ${scale}x text: $perRow button(s) per '
          'row, no overflow', (tester) async {
        await show(tester, size: Size(width, 1600), textScale: scale);
        expect(tester.takeException(), isNull);
        final a = tester.getTopLeft(find.text('Export…'));
        final b = tester.getTopLeft(find.text('Import…'));
        if (perRow == 1) {
          expect(b.dy, greaterThan(a.dy));
        } else {
          expect(b.dy, a.dy);
        }
        final size = tester.getSize(
          find.ancestor(
            of: find.text('Delete everything…'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(24));
        expect(size.width, greaterThanOrEqualTo(24));
      });
    }
  });

  group('export dialog', () {
    testWidgets('title, text, tick box unticked with its count, warning; '
        'focus on Cancel; tab order tick box, Cancel, Save…', (tester) async {
      await show(tester);
      seedHistory(2);
      await tapHook(tester, 'your-data-export');
      expect(find.text('Export your data'), findsOneWidget);
      expect(
        find.text('Your snippets and settings will be saved to a file.'),
        findsOneWidget,
      );
      expect(find.text('Include history (2 items)'), findsOneWidget);
      expect(
        find.text("The file isn't encrypted. Anyone who opens it can read it."),
        findsOneWidget,
      );
      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, isFalse, reason: 'D2 A: private by default');
      expect(focused(tester, 'Cancel'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(tester, 'Save…'), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(focusedCheckbox(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Export your data'), findsNothing);
      expect(
        files.saves,
        0,
        reason: 'the warning comes before the save dialog',
      );
    });

    testWidgets('1 item, and no items (disabled)', (tester) async {
      await show(tester);
      seedHistory(1);
      await tapHook(tester, 'your-data-export');
      expect(find.text('Include history (1 item)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      service.clear();
      await tester.pump();
      await tapHook(tester, 'your-data-export');
      expect(find.text('Include history (no items)'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    });

    testWidgets('Save… writes the file, closes, and toasts the counts', (
      tester,
    ) async {
      await show(tester);
      service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
      seedHistory(2);
      files.savePath = p.join(dir.path, 'out.json');
      await tapHook(tester, 'your-data-export');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(hook('export-save'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Export your data'), findsNothing);
      expect(
        find.text('Exported 1 snippet and 2 history items'),
        findsOneWidget,
      );
      expect(File(files.savePath!).existsSync(), isTrue);
    });

    testWidgets('without history the toast names snippets only', (
      tester,
    ) async {
      await show(tester);
      files.savePath = p.join(dir.path, 'out.json');
      await tapHook(tester, 'your-data-export');
      await tester.runAsync(() async {
        await tester.tap(hook('export-save'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Exported 0 snippets'), findsOneWidget);
    });

    testWidgets('save dialog cancelled: the dialog stays, no message', (
      tester,
    ) async {
      await show(tester);
      await tapHook(tester, 'your-data-export');
      await tester.runAsync(() async {
        await tester.tap(hook('export-save'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(find.text('Export your data'), findsOneWidget);
      expect(find.text("Couldn't save the export. Try again."), findsNothing);
    });

    testWidgets('write failed: the dialog stays with the error, announced', (
      tester,
    ) async {
      await show(tester);
      files.savePath = p.join(dir.path, 'no-such-folder', 'out.json');
      await tapHook(tester, 'your-data-export');
      await tester.runAsync(() async {
        await tester.tap(hook('export-save'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Export your data'), findsOneWidget);
      final error = find.text("Couldn't save the export. Try again.");
      expect(error, findsOneWidget);
      expect(liveRegionAround(error), findsOneWidget);
    });
  });

  group('import', () {
    void writeFile(
      ExportBundle b, [
      String name = 'kusunga-export-2026-11-12.json',
    ]) {
      files.openPath = p.join(dir.path, name);
      File(
        files.openPath!,
      ).writeAsStringSync(encodeExport(b, exportedAt: DateTime.utc(2026)));
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    ExportHistoryItem h(String c) => ExportHistoryItem(
      content: c,
      kind: ClipKind.text,
      createdAt: now,
      lastCopiedAt: now,
    );

    Future<void> pickFile(WidgetTester tester) async {
      await tester.ensureVisible(hook('your-data-import'));
      await tester.tap(hook('your-data-import'));
      await settle(tester);
    }

    testWidgets('cancelled: nothing happens', (tester) async {
      await show(tester);
      await pickFile(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Import…'), findsOneWidget);
    });

    testWidgets('while checking, the button reads "Checking the file…" and '
        'is disabled (G4)', (tester) async {
      await show(tester);
      final gate = files.holdOpen();
      await tester.ensureVisible(hook('your-data-import'));
      await tester.tap(hook('your-data-import'));
      await tester.pump();
      expect(find.text('Checking the file…'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Checking the file…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      gate.complete(null);
      await tester.pump();
      await tester.pump();
      expect(find.text('Import…'), findsOneWidget);
    });

    testWidgets('refused: a toast (G4), nothing changes', (tester) async {
      await show(tester);
      files.openPath = p.join(dir.path, 'x.json');
      File(files.openPath!).writeAsStringSync('not json');
      await pickFile(tester);
      expect(
        find.text(
          "This file can't be imported. It isn't a Kusunga export, or it is "
          'damaged.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirm: title with the file name, counts, settings tick '
        'box unticked, focus on Cancel; Import adds and toasts', (
      tester,
    ) async {
      await show(tester);
      writeFile(
        ExportBundle(
          snippets: const [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
            ExportSnippet(
              name: 'B',
              content: 'b',
              type: SnippetType.other,
              position: 1,
            ),
          ],
          history: [h('one')],
          settings: const ExportSettings(historyLimit: 10),
        ),
      );
      await pickFile(tester);
      expect(
        find.text('Import from kusunga-export-2026-11-12.json'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Import 2 snippets and 1 history item? Nothing you have now will be '
          'changed or removed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Also use the settings in this file'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(focused(tester, 'Cancel'), isTrue);
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Imported 2 snippets and 1 history item.'),
        findsOneWidget,
      );
      expect(service.snippets.items.length, 2);
      expect(service.limit, 200, reason: 'settings not ticked');
      expect(afterImports, 0);
    });

    testWidgets('ticked settings apply, and the app reloads them', (
      tester,
    ) async {
      await show(tester);
      writeFile(
        const ExportBundle(
          snippets: [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
          settings: ExportSettings(historyLimit: 10),
        ),
      );
      await pickFile(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(service.limit, 10);
      expect(afterImports, 1);
    });

    testWidgets('the history count is rows, not lines, and follows the '
        'settings tick box as it changes; Import adds that many (T4)', (
      tester,
    ) async {
      await show(tester);
      service.setLimit(10);
      seedHistory(10);
      final old = now - Duration.millisecondsPerDay;
      ExportHistoryItem older(String c) => ExportHistoryItem(
        content: c,
        kind: ClipKind.text,
        createdAt: old,
        lastCopiedAt: old,
      );
      writeFile(
        ExportBundle(
          snippets: const [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
          history: [older('x'), older('x'), older('y'), older('z')],
          settings: const ExportSettings(historyLimit: 50),
        ),
      );
      await pickFile(tester);
      String text(int n) =>
          'Import 1 snippet and $n history ${n == 1 ? 'item' : 'items'}? '
          'Nothing you have now will be changed or removed.';
      // Limit 10, and the 10 items here are all newer: nothing would stay.
      expect(find.text(text(0)), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      // The file's limit of 50: x, y and z, with x once.
      expect(find.text(text(3)), findsOneWidget);
      expect(find.text(text(0)), findsNothing);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text(text(0)), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(
        find.text('Imported 1 snippet and 3 history items.'),
        findsOneWidget,
      );
      expect(service.items.length, 13);
    });

    testWidgets('with a full history, ticking a lower limit deletes '
        'nothing: the confirm still says nothing is removed, and the toast '
        'says what was kept out and unchanged (R1)', (tester) async {
      await show(tester);
      service.setLimit(20);
      seedHistory(20);
      final before = service.items.map((i) => i.preview).toList();
      writeFile(
        ExportBundle(
          snippets: const [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
          history: [h('x'), h('y')],
          settings: const ExportSettings(historyLimit: 10),
        ),
      );
      await pickFile(tester);
      const text =
          'Import 1 snippet and 0 history items? Nothing you have now will '
          'be changed or removed.';
      expect(find.text(text), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text(text), findsOneWidget, reason: 'the same when ticked');
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(
        find.text(
          'Imported 1 snippet and 0 history items. 2 history items didn\'t '
          "fit under your history limit and weren't added. Your history "
          "limit wasn't changed, because that would delete items. Change it "
          'in Settings.',
        ),
        findsOneWidget,
      );
      expect(service.items.map((i) => i.preview), before);
      expect(service.limit, 20);
    });

    testWidgets('no settings in the file: no tick box', (tester) async {
      await show(tester);
      writeFile(
        const ExportBundle(
          snippets: [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
        ),
      );
      await pickFile(tester);
      expect(find.text('Also use the settings in this file'), findsNothing);
    });

    testWidgets('the toast adds what was skipped', (tester) async {
      await show(tester);
      service.snippets.save(
        name: 'A',
        content: 'a',
        type: SnippetType.other,
        shortcut: ';a',
      );
      service.snippets.save(name: 'B', content: 'b', type: SnippetType.other);
      service.expiry.setDays(1);
      writeFile(
        ExportBundle(
          snippets: const [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
            ExportSnippet(
              name: 'B',
              content: 'b',
              type: SnippetType.other,
              position: 1,
            ),
            ExportSnippet(
              name: 'C',
              content: 'c',
              type: SnippetType.other,
              position: 2,
              shortcut: ';a',
            ),
          ],
          history: [
            h('new'),
            ExportHistoryItem(
              content: 'old',
              kind: ClipKind.text,
              createdAt: 0,
              lastCopiedAt: now - 3 * Duration.millisecondsPerDay,
            ),
            ExportHistoryItem(
              content: 'old2',
              kind: ClipKind.text,
              createdAt: 0,
              lastCopiedAt: now - 3 * Duration.millisecondsPerDay,
            ),
          ],
        ),
      );
      await pickFile(tester);
      expect(
        find.text(
          'Import 3 snippets and 1 history item? Nothing you have now will be '
          'changed or removed.',
        ),
        findsOneWidget,
      );
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(
        find.text(
          'Imported 1 snippet and 1 history item. 2 snippets were already '
          'here. 1 shortcut was already used, so that snippet has none. 2 '
          "history items were older than your auto-delete time and weren't "
          'added.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing to import: only Close', (tester) async {
      await show(tester);
      writeFile(const ExportBundle(snippets: []));
      await pickFile(tester);
      expect(find.text('This file has nothing to import.'), findsOneWidget);
      expect(find.text('Import'), findsNothing);
      expect(focused(tester, 'Close'), isTrue);
      await tester.tap(hook('import-empty-close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a file with only settings and ignored apps: its own line, '
        'the tick box, and Import works only once it is ticked (R4)', (
      tester,
    ) async {
      await show(tester);
      writeFile(
        const ExportBundle(
          snippets: [],
          settings: ExportSettings(historyLimit: 300),
          ignoredApps: [IgnoredApp('com.example.vault', 'Vault')],
        ),
      );
      await pickFile(tester);
      expect(
        find.text(
          'This file has settings and ignored apps, but no snippets or '
          'history.',
        ),
        findsOneWidget,
      );
      expect(find.text('This file has nothing to import.'), findsNothing);
      expect(find.text('Also use the settings in this file'), findsOneWidget);
      expect(focused(tester, 'Cancel'), isTrue);
      FilledButton import() => tester.widget<FilledButton>(
        find.descendant(
          of: hook('import-confirm'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(import().onPressed, isNull, reason: 'not ticked yet');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(import().onPressed, isNotNull);
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Imported the settings and ignored apps in this file.'),
        findsOneWidget,
        reason: 'R8',
      );
      expect(service.limit, 300);
      expect(
        service.ignoredApps.list().any((a) => a.appId == 'com.example.vault'),
        isTrue,
      );
      expect(afterImports, 1);
    });

    testWidgets('a write failure: the dialog stays with the error; nothing '
        'changed', (tester) async {
      final flaky = FlakyStore(
        SqliteHistoryStore.open(path: p.join(dir.path, 'f.db'), keyHex: _key),
      );
      final inner = flaky.inner as SqliteHistoryStore;
      await show(
        tester,
        history: HistoryService(
          store: flaky,
          source: source,
          log: log,
          snippetStore: inner.snippetStore(),
          ignoredAppStore: inner.ignoredAppStore(),
        )..start(),
      );
      writeFile(
        const ExportBundle(
          snippets: [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
        ),
      );
      await pickFile(tester);
      flaky.failWrites = true;
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      final error = find.text("Couldn't import. Nothing was changed.");
      expect(error, findsOneWidget);
      expect(liveRegionAround(error), findsOneWidget);
      expect(service.snippets.items, isEmpty);
    });

    testWidgets('a long file name is shortened in the middle', (tester) async {
      await show(tester, size: const Size(360, 900));
      writeFile(
        const ExportBundle(
          snippets: [
            ExportSnippet(
              name: 'A',
              content: 'a',
              type: SnippetType.other,
              position: 0,
            ),
          ],
        ),
        '${'very-long-name-' * 8}end.json',
      );
      await pickFile(tester);
      final title = find.textContaining('Import from ');
      final text = tester.widget<Text>(title).data!;
      expect(text, contains('…'));
      expect(text, endsWith('end.json'));
      expect(tester.takeException(), isNull);
    });
  });

  group('Delete all history', () {
    testWidgets('the Clear history dialog; confirm deletes history only', (
      tester,
    ) async {
      await show(tester);
      service.snippets.save(
        name: 'Keep',
        content: 'k',
        type: SnippetType.other,
      );
      seedHistory(3);
      await tester.pump();
      await tapHook(tester, 'your-data-delete-history');
      expect(find.text('Clear all history?'), findsOneWidget);
      expect(
        find.text('This deletes all 3 items. Snippets are not affected.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(service.items, isEmpty);
      expect(service.snippets.items.length, 1);
    });
  });

  group('Delete everything', () {
    testWidgets('lists what goes with counts; focus on Cancel; Cancel keeps '
        'everything', (tester) async {
      await show(tester);
      service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
      seedHistory(2);
      await tester.pump();
      await tapHook(tester, 'your-data-delete-everything');
      expect(find.text('Delete everything?'), findsOneWidget);
      for (final line in [
        'This removes from this computer:',
        '• all history (2 items)',
        '• all snippets (1)',
        '• your settings and ignored apps',
        "• Kusunga's key and log",
        'Launch at login is turned off, and Kusunga quits. This can\'t be '
            'undone. Export first if you want a copy.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(focused(tester, 'Cancel'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Delete everything?'), findsNothing);
      expect(keys.stored, _key);
      expect(service.items.length, 2);
    });

    testWidgets('counts may be 0; the list still shows', (tester) async {
      await show(tester);
      await tapHook(tester, 'your-data-delete-everything');
      expect(find.text('• all history (0 items)'), findsOneWidget);
      expect(find.text('• all snippets (0)'), findsOneWidget);
    });

    testWidgets('confirm: done message with OK, which quits', (tester) async {
      await show(tester);
      seedHistory(1);
      await tapHook(tester, 'your-data-delete-everything');
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(
        find.text('Everything is deleted. Kusunga will now quit.'),
        findsOneWidget,
      );
      expect(keys.stored, isNull);
      expect(File(p.join(dir.path, 'kusunga.db')).existsSync(), isFalse);
      expect(quits, 0);
      await tester.tap(hook('delete-everything-ok'));
      await tester.pumpAndSettle();
      expect(quits, 1);
    });

    testWidgets('key delete failed: the dialog stays with the error, '
        'nothing deleted; Try again works', (tester) async {
      await show(tester);
      keys.deleteError = StateError('denied');
      await tapHook(tester, 'your-data-delete-everything');
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      final error = find.text(
        "Couldn't delete everything. Nothing was deleted. Try again.",
      );
      expect(error, findsOneWidget);
      expect(liveRegionAround(error), findsOneWidget);
      expect(File(p.join(dir.path, 'kusunga.db')).existsSync(), isTrue);
      expect(quits, 0);
      keys.deleteError = null;
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(
        find.text('Everything is deleted. Kusunga will now quit.'),
        findsOneWidget,
      );
    });

    testWidgets('the keychain never answers: the note says Kusunga stopped '
        'recording and will quit; its one button, OK, quits; recording '
        'stays stopped (T5)', (tester) async {
      await show(tester, keyTimeout: const Duration(milliseconds: 20));
      keys.holdDelete(); // never answers
      await tapHook(tester, 'your-data-delete-everything');
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      final note = find.text(
        "Kusunga couldn't confirm whether its key was deleted, so it has "
        'stopped recording and will now quit. Open Kusunga again. If your '
        'snippets and history are still there, try Delete everything again.',
      );
      expect(note, findsOneWidget);
      expect(liveRegionAround(note), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsOneWidget,
        reason: 'OK only: no Cancel, no Try again',
      );
      expect(find.text('Delete everything'), findsNothing);
      expect(
        find.text(
          "Couldn't delete everything. Nothing was deleted. Try again.",
        ),
        findsNothing,
      );
      expect(focused(tester, 'OK'), isTrue);
      expect(File(p.join(dir.path, 'kusunga.db')).existsSync(), isTrue);
      expect(steps, isEmpty, reason: 'the log file is not stopped');
      source.copy('after');
      await tester.pump();
      expect(service.items, isEmpty);
      expect(quits, 0);
      await tester.tap(hook('delete-everything-ok'));
      await tester.pumpAndSettle();
      expect(quits, 1);
    });

    testWidgets('a debug data profile with a file left: the profile wording, '
        'never "can\'t be read any more"; OK quits (T10)', (tester) async {
      await show(
        tester,
        target: ProfileEraseTarget(
          folder: () async => throw const FileSystemException(
            'denied',
            '',
            OSError('denied', 13),
          ),
        ),
      );
      await tapHook(tester, 'your-data-delete-everything');
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      final note = find.text(
        "Everything is deleted. 1 file in this test profile couldn't be "
        'removed.',
      );
      expect(note, findsOneWidget);
      expect(liveRegionAround(note), findsOneWidget);
      expect(find.textContaining("can't be read any more"), findsNothing);
      expect(keys.deletes, 0, reason: 'the shared key stays');
      await tester.tap(hook('delete-everything-ok'));
      await tester.pumpAndSettle();
      expect(quits, 1);
    });

    testWidgets('what is left may not be an encrypted database file: the '
        'partial message without "can\'t be read any more" (R7a)', (
      tester,
    ) async {
      await show(
        tester,
        target: DefaultEraseTarget(
          keys: keys,
          folder: () async => throw const FileSystemException(
            'denied',
            '',
            OSError('denied', 13),
          ),
        ),
      );
      await tapHook(tester, 'your-data-delete-everything');
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      final note = find.text(
        "Everything is deleted. 1 file couldn't be removed.",
      );
      expect(note, findsOneWidget);
      expect(liveRegionAround(note), findsOneWidget);
      expect(find.textContaining("can't be read any more"), findsNothing);
      await tester.tap(hook('delete-everything-ok'));
      await tester.pumpAndSettle();
      expect(quits, 1);
    });

    testWidgets('a debug data profile with nothing left: the usual done '
        'message (T10)', (tester) async {
      final profile = Directory(p.join(dir.path, 'profiles', 'qa'))
        ..createSync(recursive: true);
      File(p.join(profile.path, 'kusunga.log')).writeAsStringSync('x');
      await show(
        tester,
        target: ProfileEraseTarget(folder: () async => profile),
      );
      await tapHook(tester, 'your-data-delete-everything');
      await tester.runAsync(() async {
        await tester.tap(hook('delete-everything-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(
        find.text('Everything is deleted. Kusunga will now quit.'),
        findsOneWidget,
      );
      expect(profile.existsSync(), isFalse);
    });

    testWidgets('while deleting: "Deleting…", input ignored', (tester) async {
      await show(tester);
      final gate = keys.holdDelete();
      await tapHook(tester, 'your-data-delete-everything');
      await tester.tap(hook('delete-everything-confirm'));
      await tester.pump();
      expect(find.text('Deleting…'), findsOneWidget);
      final cancel = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(TextButton),
        ),
      );
      expect(cancel.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Deleting…'), findsOneWidget);
      gate.completeError(StateError('denied'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
    });
  });

  test('the partial wording when what is left may be readable (R7a)', () {
    expect(
      plainPartialMessage(1),
      "Everything is deleted. 1 file couldn't be removed.",
    );
    expect(
      plainPartialMessage(3),
      "Everything is deleted. 3 files couldn't be removed.",
    );
  });

  test('the partial wording in a debug data profile, whose key stays '
      '(T10; lead wording, 2026-11-12)', () {
    expect(
      profilePartialMessage(1),
      "Everything is deleted. 1 file in this test profile couldn't be "
      'removed.',
    );
    expect(
      profilePartialMessage(2),
      "Everything is deleted. 2 files in this test profile couldn't be "
      'removed.',
    );
  });

  test('count wording', () {
    expect(
      partialMessage(1),
      "Everything is deleted. 1 file couldn't be removed, but it can't be "
      'read any more.',
    );
    expect(
      partialMessage(2),
      "Everything is deleted. 2 files couldn't be removed, but they can't "
      'be read any more.',
    );
    expect(exportedMessage(1, null), 'Exported 1 snippet');
    expect(exportedMessage(2, 1), 'Exported 2 snippets and 1 history item');
    expect(
      importedMessage(const ImportCounts(snippetsAdded: 1, historyAdded: 2)),
      'Imported 1 snippet and 2 history items.',
    );
    expect(
      importedMessage(
        const ImportCounts(
          snippetsAlreadyHere: 1,
          shortcutsDropped: 2,
          historyTooOld: 1,
        ),
      ),
      'Nothing was imported. 1 snippet was already here. '
      '2 shortcuts were already used, so those snippets have none. 1 history '
      "item was older than your auto-delete time and wasn't added.",
    );
  });

  test('nothing added but the settings applied: the toast says so, then '
      'every sentence that applies (R8; lead copy, 2026-11-13)', () {
    const head = 'Imported the settings and ignored apps in this file.';
    expect(importedMessage(const ImportCounts(settingsApplied: true)), head);
    expect(
      importedMessage(
        const ImportCounts(
          settingsApplied: true,
          snippetsAlreadyHere: 2,
          limitKept: true,
        ),
      ),
      '$head 2 snippets were already here. Your history limit wasn\'t '
      'changed, because that would delete items. Change it in Settings.',
    );
    expect(
      importedMessage(
        const ImportCounts(settingsApplied: true, historyAdded: 1),
      ),
      'Imported 0 snippets and 1 history item.',
      reason: 'something was added: the usual line',
    );
    expect(
      importedMessage(const ImportCounts()),
      'Nothing was imported.',
      reason: 'R10: nothing added or changed',
    );
    expect(
      importedMessage(const ImportCounts(limitKept: true)),
      "Nothing was imported. Your history limit wasn't changed, because "
      'that would delete items. Change it in Settings.',
      reason: 'R10: a kept setting is not an applied one',
    );
  });

  test('the import toast says what never deletes history kept out or '
      'unchanged (R1; lead copy, 2026-11-13)', () {
    String m(ImportCounts c) => importedMessage(c);
    // Nothing added or changed in these: R10's line.
    const head = 'Nothing was imported.';
    expect(
      m(const ImportCounts(snippetsAlreadyHere: 2, historyAlreadyHere: 1)),
      '$head 2 snippets were already here. 1 history item was already here.',
      reason: 'R9: right after the snippets one',
    );
    expect(
      m(const ImportCounts(historyAlreadyHere: 3)),
      '$head 3 history items were already here.',
    );
    expect(
      m(const ImportCounts(historyNoRoom: 1)),
      "$head 1 history item didn't fit under your history limit and wasn't "
      'added.',
    );
    expect(
      m(const ImportCounts(historyNoRoom: 3)),
      "$head 3 history items didn't fit under your history limit and "
      "weren't added.",
    );
    expect(
      m(const ImportCounts(limitKept: true, expiryKept: true)),
      "$head Your history limit and auto-delete weren't changed, because "
      'that would delete items. Change them in Settings.',
    );
    expect(
      m(const ImportCounts(limitKept: true)),
      "$head Your history limit wasn't changed, because that would delete "
      'items. Change it in Settings.',
    );
    expect(
      m(const ImportCounts(expiryKept: true)),
      "$head Your auto-delete time wasn't changed, because that would "
      'delete items. Change it in Settings.',
    );
    expect(
      m(
        const ImportCounts(historyTooOld: 1, historyNoRoom: 2, limitKept: true),
      ),
      "$head 1 history item was older than your auto-delete time and wasn't "
      "added. 2 history items didn't fit under your history limit and "
      "weren't added. Your history limit wasn't changed, because that would "
      'delete items. Change it in Settings.',
    );
  });
}
