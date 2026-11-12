// M1.8 tester: UI states of Your data that the build's own widget tests do
// not reach (docs/ui/your-data.md, states matrix, accessibility notes and
// copy): Escape and Cancel on every dialog, a second click while working,
// the barrier during "Deleting…", singular copy, the partial-delete message,
// the narrow 320 px / 200% layout with each dialog open, Delete all history,
// and backup-failed / memory-only sessions. Fakes and temp folders only.
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
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/settings/ui/your_data_section.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _importHelp =
    "Import isn't available right now, because history isn't being saved.";

void main() {
  late Directory dir;
  late FakeClipboardSource source;
  late FakeLog log;
  late FakeFilePort files;
  late FakeKeyStore keys;
  late HistoryService service;
  late int quits;
  late int afterImports;
  void Function(FileSystemEntity)? deleteEntity;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_ui_');
    source = FakeClipboardSource();
    log = FakeLog();
    files = FakeFilePort();
    keys = FakeKeyStore(stored: _key);
    quits = 0;
    afterImports = 0;
    deleteEntity = null;
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

  HistoryService memoryService(Set<HistoryNotice> notices) => HistoryService(
    store: MemoryHistoryStore(),
    source: source,
    log: log,
    notices: notices,
  )..start();

  Future<void> show(
    WidgetTester tester, {
    HistoryService? history,
    Size size = const Size(800, 1200),
    double textScale = 1,
    Duration keyTimeout = const Duration(seconds: 30),
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
              target: DefaultEraseTarget(keys: keys, folder: () async => dir),
              log: log,
              stopFileLog: () {},
              deleteEntity: deleteEntity,
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  void seedHistory(int n) {
    for (var i = 0; i < n; i++) {
      source.copy('item $i');
    }
  }

  /// Which button holds the primary focus, by its label.
  String? focusedLabel() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    String? label;
    ctx.visitAncestorElements((e) {
      final w = e.widget;
      if (w is ButtonStyleButton) {
        final text = find.descendant(
          of: find.byWidget(w),
          matching: find.byType(Text),
        );
        if (text.evaluate().isNotEmpty) {
          label = tester0Text(text);
        }
        return false;
      }
      return true;
    });
    return label;
  }

  bool buttonEnabled(WidgetTester tester, String label) {
    final w = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    return w.onPressed != null;
  }

  String exportBundleFile(ExportBundle b, [String name = 'in.json']) {
    final path = p.join(dir.path, name);
    File(
      path,
    ).writeAsStringSync(encodeExport(b, exportedAt: DateTime.utc(2026)));
    return path;
  }

  ExportSnippet snip(String n, {String? shortcut}) => ExportSnippet(
    name: n,
    content: 'content of $n',
    type: SnippetType.other,
    position: 0,
    shortcut: shortcut,
  );

  group('Escape and Cancel change nothing', () {
    testWidgets('the import confirm: Cancel is focused; Escape adds '
        'nothing and the settings stay as they were', (tester) async {
      await show(tester);
      final limit = service.limit;
      files.openPath = exportBundleFile(
        ExportBundle(
          snippets: [snip('A')],
          history: [
            ExportHistoryItem(
              content: 'h',
              kind: ClipKind.text,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              lastCopiedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
          settings: const ExportSettings(historyLimit: 25),
        ),
      );
      await tester.ensureVisible(hook('your-data-import'));
      await tester.tap(hook('your-data-import'));
      await settle(tester);
      expect(find.text('Import 1 snippet and 1 history item?'), findsNothing);
      expect(
        find.textContaining('Import 1 snippet and 1 history item?'),
        findsOneWidget,
        reason: 'singular: 1 snippet, 1 history item',
      );
      expect(focusedLabel(), 'Cancel');
      // tick the settings box, then Escape: still nothing happens
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.textContaining('Import 1 snippet'), findsNothing);
      expect(service.snippets.records(), isEmpty);
      expect(service.items, isEmpty);
      expect(service.limit, limit);
      expect(afterImports, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the import confirm: tapping outside the dialog is also a '
        'cancel', (tester) async {
      await show(tester);
      files.openPath = exportBundleFile(ExportBundle(snippets: [snip('A')]));
      await tester.ensureVisible(hook('your-data-import'));
      await tester.tap(hook('your-data-import'));
      await settle(tester);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.snippets.records(), isEmpty);
    });

    testWidgets('the export dialog: Cancel closes it, no save dialog, no '
        'file, no toast', (tester) async {
      await show(tester);
      await tapHook(tester, 'your-data-export');
      expect(focusedLabel(), 'Cancel');
      await tester.tap(hook('export-cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Export your data'), findsNothing);
      expect(files.saves, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Delete everything: Cancel and tapping outside keep every '
        'file, the key and the quit', (tester) async {
      await show(tester);
      seedHistory(1);
      await tapHook(tester, 'your-data-delete-everything');
      await tester.tap(hook('delete-everything-cancel'));
      await tester.pumpAndSettle();
      await tapHook(tester, 'your-data-delete-everything');
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Delete everything?'), findsNothing);
      expect(keys.stored, _key);
      expect(keys.deletes, 0);
      expect(File(p.join(dir.path, 'kusunga.db')).existsSync(), isTrue);
      expect(quits, 0);
    });
  });

  group('a second click while working does nothing more', () {
    testWidgets('Delete everything: two taps on the button delete the key '
        'once, and a tap outside during "Deleting…" keeps the dialog', (
      tester,
    ) async {
      await show(tester);
      final gate = keys.holdDelete();
      await tapHook(tester, 'your-data-delete-everything');
      await tester.tap(hook('delete-everything-confirm'));
      await tester.pump();
      expect(find.text('Deleting…'), findsOneWidget);
      await tester.tap(hook('delete-everything-confirm'), warnIfMissed: false);
      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      expect(find.text('Deleting…'), findsOneWidget);
      expect(find.text('Delete everything?'), findsOneWidget);
      await tester.runAsync(() async {
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(keys.deletes, 1);
      expect(
        find.text('Everything is deleted. Kusunga will now quit.'),
        findsOneWidget,
      );
      expect(quits, 0, reason: 'quits only after OK');
      await tester.tap(hook('delete-everything-ok'));
      await tester.pumpAndSettle();
      expect(quits, 1);
    });

    testWidgets('Import…: a second tap while the file is checked opens one '
        'open dialog only', (tester) async {
      await show(tester);
      final gate = files.holdOpen();
      await tester.ensureVisible(hook('your-data-import'));
      await tester.tap(hook('your-data-import'));
      await tester.pump();
      expect(find.text('Checking the file…'), findsOneWidget);
      await tester.tap(hook('your-data-import'), warnIfMissed: false);
      await tester.pump();
      expect(files.opens, 1);
      await tester.runAsync(() async {
        gate.complete(null);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(find.text('Import…'), findsOneWidget);
    });

    testWidgets('Export: two taps on Save… write once', (tester) async {
      await show(tester);
      files.savePath = p.join(dir.path, 'out.json');
      await tapHook(tester, 'your-data-export');
      await tester.runAsync(() async {
        await tester.tap(hook('export-save'));
        await tester.tap(hook('export-save'), warnIfMissed: false);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(files.saves, 1);
      expect(log.codes.where((c) => c == LogCode.dataExported), hasLength(1));
    });
  });

  group('copy and plurals', () {
    testWidgets('Delete everything with 1 item and 1 snippet', (tester) async {
      await show(tester);
      service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
      seedHistory(1);
      await tester.pump();
      await tapHook(tester, 'your-data-delete-everything');
      expect(find.text('• all history (1 item)'), findsOneWidget);
      expect(find.text('• all snippets (1)'), findsOneWidget);
    });

    testWidgets('the partial message when a file will not go: one file, '
        'then two', (tester) async {
      for (final (n, message) in [
        (
          1,
          "Everything is deleted. 1 file couldn't be removed, but it can't "
              'be read any more.',
        ),
        (
          2,
          "Everything is deleted. 2 files couldn't be removed, but they "
              "can't be read any more.",
        ),
      ]) {
        File(p.join(dir.path, 'kusunga.log')).writeAsStringSync('x');
        File(p.join(dir.path, 'kusunga.log.1')).writeAsStringSync('x');
        var failed = 0;
        deleteEntity = (e) {
          final name = p.basename(e.path);
          if (failed < n && name.startsWith('kusunga.log')) {
            failed++;
            throw const FileSystemException('busy', '', OSError('busy', 16));
          }
          e.deleteSync();
        };
        await show(tester);
        await tapHook(tester, 'your-data-delete-everything');
        await tester.runAsync(() async {
          await tester.tap(hook('delete-everything-confirm'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(find.text(message), findsOneWidget, reason: '$n');
        expect(keys.stored, isNull);
        await tester.tap(hook('delete-everything-ok'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        keys = FakeKeyStore(stored: _key);
        for (final f in dir.listSync()) {
          f.deleteSync(recursive: true);
        }
      }
      expect(quits, 2);
    });

    testWidgets('the import toast names every skip, with the singular forms', (
      tester,
    ) async {
      await show(tester);
      service.snippets.save(
        name: 'Here',
        content: 'content of Here',
        type: SnippetType.other,
        shortcut: ';taken',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      files.openPath = exportBundleFile(
        ExportBundle(
          snippets: [
            snip('Here'),
            snip('New', shortcut: ';taken'),
          ],
          history: [
            ExportHistoryItem(
              content: 'old',
              kind: ClipKind.text,
              createdAt: 0,
              lastCopiedAt: now - 400 * Duration.millisecondsPerDay,
            ),
            ExportHistoryItem(
              content: 'new',
              kind: ClipKind.text,
              createdAt: now,
              lastCopiedAt: now,
            ),
          ],
        ),
      );
      await tester.ensureVisible(hook('your-data-import'));
      await tester.tap(hook('your-data-import'));
      await settle(tester);
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(
        find.text(
          'Imported 1 snippet and 1 history item. 1 snippet was already here. '
          '1 shortcut was already used, so that snippet has none. 1 history '
          "item was older than your auto-delete time and wasn't added.",
        ),
        findsOneWidget,
      );
    });
  });

  group('Delete all history', () {
    testWidgets('Escape keeps the history; confirming deletes only history: '
        'snippets, settings and the key stay, and the button turns off', (
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
      expect(focusedLabel(), 'Cancel');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(service.items, hasLength(3));

      await tapHook(tester, 'your-data-delete-history');
      expect(find.textContaining('3'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();
      expect(service.items, isEmpty);
      expect(service.snippets.records().single.name, 'Keep');
      expect(keys.stored, _key);
      expect(keys.deletes, 0);
      expect(File(p.join(dir.path, 'kusunga.db')).existsSync(), isTrue);
      expect(buttonEnabled(tester, 'Delete all history…'), isFalse);
      expect(quits, 0);
    });
  });

  group('sessions where history is not saved', () {
    for (final (name, notice) in [
      ('backup failed', HistoryNotice.backupFailed),
      ('incompatible', HistoryNotice.incompatible),
      ('memory only', HistoryNotice.memoryOnly),
    ]) {
      testWidgets('$name: Import… is off, with its line; tapping it opens '
          'no dialog', (tester) async {
        await show(tester, history: memoryService({notice}));
        expect(find.text(_importHelp), findsOneWidget);
        expect(buttonEnabled(tester, 'Import…'), isFalse);
        await tester.ensureVisible(hook('your-data-import'));
        await tester.tap(hook('your-data-import'), warnIfMissed: false);
        await tester.pump();
        expect(files.opens, 0);
        expect(buttonEnabled(tester, 'Export…'), isTrue);
        expect(buttonEnabled(tester, 'Delete everything…'), isTrue);
      });
    }

    testWidgets('a normal session shows no import help line', (tester) async {
      await show(tester);
      expect(find.text(_importHelp), findsNothing);
      expect(buttonEnabled(tester, 'Import…'), isTrue);
    });

    testWidgets('memory only: Delete everything empties the memory, tries '
        'the key, and quits after OK', (tester) async {
      source = FakeClipboardSource();
      await show(tester, history: memoryService({HistoryNotice.memoryOnly}));
      seedHistory(2);
      keys.deleteError = StateError('no keychain');
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
      expect(service.items, isEmpty);
      await tester.tap(hook('delete-everything-ok'));
      await tester.pumpAndSettle();
      expect(quits, 1);
    });
  });

  group('the narrow layout (320 px, and 360 px at 200% text) with each '
      'dialog open', () {
    for (final (width, scale) in [(320.0, 1.0), (360.0, 2.0), (320.0, 2.0)]) {
      testWidgets('$width px at ${scale}x: no overflow, every button '
          'reachable and at least 24 px', (tester) async {
        await show(tester, size: Size(width, 700), textScale: scale);
        seedHistory(2);
        service.snippets.save(name: 'A', content: 'a', type: SnippetType.other);
        await tester.pump();

        Future<void> check(String dialogHook, List<String> buttons) async {
          await tapHook(tester, dialogHook);
          expect(tester.takeException(), isNull, reason: dialogHook);
          for (final id in buttons) {
            final f = hook(id);
            expect(f, findsOneWidget, reason: id);
            final r = tester.getRect(f);
            expect(r.height, greaterThanOrEqualTo(24), reason: id);
            expect(r.width, greaterThanOrEqualTo(24), reason: id);
            expect(r.left, greaterThanOrEqualTo(0), reason: id);
            expect(r.right, lessThanOrEqualTo(width + 0.5), reason: id);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }

        await check('your-data-export', ['export-cancel', 'export-save']);
        await check('your-data-delete-everything', [
          'delete-everything-cancel',
          'delete-everything-confirm',
        ]);

        files.openPath = exportBundleFile(
          ExportBundle(
            snippets: [snip(('A very long snippet name ' * 3).trim())],
            settings: const ExportSettings(historyLimit: 50),
          ),
          'a-very-long-file-name-for-a-kusunga-export-from-last-year-2026-11-12.json',
        );
        await tester.ensureVisible(hook('your-data-import'));
        await tester.tap(hook('your-data-import'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        for (final id in ['import-cancel', 'import-confirm']) {
          expect(hook(id), findsOneWidget, reason: id);
          expect(
            tester.getRect(hook(id)).right,
            lessThanOrEqualTo(width + 0.5),
          );
        }
        // the whole dialog is reachable by scrolling, not cut off
        expect(find.text('Also use the settings in this file'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      });
    }
  });
}

String tester0Text(Finder f) => (f.evaluate().first.widget as Text).data ?? '';
