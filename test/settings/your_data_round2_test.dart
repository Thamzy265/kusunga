// M1.8 tester, round 2 re-check: R4 (a file with only settings and ignored
// apps), the R1 toast sentences, and R2 (Undo after any clear) in the UI.
// Fakes and temp folders only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/data/data_eraser.dart';
import 'package:kusunga/data/export_format.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/sqlite_history_store.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/settings/ui/your_data_section.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _settingsOnly =
    'This file has settings and ignored apps, but no snippets or history.';

void main() {
  late Directory dir;
  late FakeFilePort files;
  late HistoryService service;
  late SqliteHistoryStore store;
  late int afterImports;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kusunga_tester_r2ui_');
    files = FakeFilePort();
    afterImports = 0;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> show(WidgetTester tester) async {
    store = SqliteHistoryStore.open(
      path: p.join(dir.path, 'kusunga.db'),
      keyHex: _key,
    );
    service = HistoryService(
      store: store,
      source: FakeClipboardSource(),
      log: FakeLog(),
      snippetStore: store.snippetStore(),
      ignoredAppStore: store.ignoredAppStore(),
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: SettingsScreen(
          service: service,
          onShowPrivacy: () {},
          yourData: YourDataSetup(
            files: files,
            log: FakeLog(),
            eraser: () => DataEraser(
              target: const NoDataEraseTarget(),
              log: FakeLog(),
              stopFileLog: () {},
            ),
            quit: () async {},
            afterImport: () async => afterImports++,
          ),
        ),
      ),
    );
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

  Future<void> openFile(WidgetTester tester, Map<String, Object?> body) async {
    files.openPath = p.join(dir.path, 'in.json');
    File(files.openPath!).writeAsStringSync(
      jsonEncode({
        'format': 'kusunga-export',
        'version': 1,
        'exported_at': '2026-11-12T09:30:00Z',
        'snippets': <Object?>[],
        ...body,
      }),
    );
    await tester.ensureVisible(hook('your-data-import'));
    await tester.tap(hook('your-data-import'));
    await settle(tester);
  }

  bool enabled(WidgetTester tester, String id) {
    final b = tester.widget<ButtonStyleButton>(
      find.descendant(
        of: hook(id),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    return b.onPressed != null;
  }

  group('R4: a file with only settings and ignored apps', () {
    testWidgets('settings only: its own line, Import is off until the box '
        'is ticked, then the settings apply', (tester) async {
      await show(tester);
      await openFile(tester, {
        'settings': {'paste_mode': 'copy_only', 'typed_shortcuts_on': 1},
      });
      expect(find.text(_settingsOnly), findsOneWidget);
      expect(find.textContaining('Nothing you have now'), findsNothing);
      expect(find.text('This file has nothing to import.'), findsNothing);
      expect(find.text('Also use the settings in this file'), findsOneWidget);
      expect(enabled(tester, 'import-confirm'), isFalse);
      expect(enabled(tester, 'import-cancel'), isTrue);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(enabled(tester, 'import-confirm'), isTrue);
      // un-ticking turns it off again
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(enabled(tester, 'import-confirm'), isFalse);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(store.readSetting('paste_mode'), 'copy_only');
      expect(store.readSetting('typed_shortcuts_on'), '1');
      expect(afterImports, 1);
    });

    testWidgets('ignored apps only counts as settings too', (tester) async {
      await show(tester);
      await openFile(tester, {
        'ignored_apps': [
          {'app_id': 'com.vault', 'display_name': 'Vault'},
        ],
      });
      expect(find.text(_settingsOnly), findsOneWidget);
      expect(enabled(tester, 'import-confirm'), isFalse);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(
        store.ignoredAppStore().list().map((a) => a.appId),
        contains('com.vault'),
      );
    });

    testWidgets('Escape and Cancel on a settings-only file change nothing', (
      tester,
    ) async {
      await show(tester);
      await openFile(tester, {
        'settings': {'paste_mode': 'copy_only'},
      });
      await tester.tap(find.byType(Checkbox));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.readSetting('paste_mode'), isNot('copy_only'));
      expect(afterImports, 0);
    });

    testWidgets('a file with nothing at all, or an empty settings object, '
        'is still "nothing to import" with only Close', (tester) async {
      await show(tester);
      for (final body in <Map<String, Object?>>[
        {},
        {'settings': <String, Object?>{}},
        {'ignored_apps': <Object?>[]},
        {'history': <Object?>[]},
      ]) {
        await openFile(tester, body);
        expect(
          find.text('This file has nothing to import.'),
          findsOneWidget,
          reason: jsonEncode(body),
        );
        expect(find.text(_settingsOnly), findsNothing);
        expect(hook('import-empty-close'), findsOneWidget);
        expect(hook('import-confirm'), findsNothing);
        await tester.tap(hook('import-empty-close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('settings plus history that is all too old: still a '
        'settings-only file', (tester) async {
      await show(tester);
      await openFile(tester, {
        'settings': {'paste_mode': 'copy_only'},
        'history': [
          {
            'content': 'ancient',
            'kind': 'text',
            'created_at': '2020-01-01T00:00:00Z',
            'last_copied_at': '2020-01-02T00:00:00Z',
          },
        ],
      });
      expect(find.text(_settingsOnly), findsOneWidget);
    });

    testWidgets('a file with a snippet and settings is the normal dialog, '
        'Import on without the tick', (tester) async {
      await show(tester);
      await openFile(tester, {
        'snippets': [
          {'name': 'A', 'content': 'a', 'type': 'other'},
        ],
        'settings': {'paste_mode': 'copy_only'},
      });
      expect(find.text(_settingsOnly), findsNothing);
      expect(enabled(tester, 'import-confirm'), isTrue);
    });

    testWidgets(
      'R8 (was BUG-R8): importing a settings-only file says what happened',
      (tester) async {
        await show(tester);
        await openFile(tester, {
          'settings': {'paste_mode': 'copy_only'},
        });
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.tap(hook('import-confirm'));
        await settle(tester);
        expect(
          find.textContaining('Imported 0 snippets and 0 history items'),
          findsNothing,
        );
        expect(
          find.text('Imported the settings and ignored apps in this file.'),
          findsOneWidget,
        );
      },
    );
  });

  group('the R1 toast sentences', () {
    String t(ImportCounts c) => importedMessage(c);

    test('no room: the singular and the plural', () {
      expect(
        t(const ImportCounts(historyNoRoom: 1)),
        "Nothing was imported. 1 history item didn't fit under your history "
        "limit and wasn't added.",
      );
      expect(
        t(const ImportCounts(historyNoRoom: 4, historyAdded: 1)),
        "Imported 0 snippets and 1 history item. 4 history items didn't fit "
        "under your history limit and weren't added.",
      );
    });

    test('kept settings: the limit, the auto-delete time, or both', () {
      expect(
        t(const ImportCounts(limitKept: true)),
        "Nothing was imported. Your history limit wasn't changed, because "
        'that would delete items. Change it in Settings.',
      );
      expect(
        t(const ImportCounts(expiryKept: true)),
        "Nothing was imported. Your auto-delete time wasn't changed, because "
        'that would delete items. Change it in Settings.',
      );
      expect(
        t(const ImportCounts(limitKept: true, expiryKept: true)),
        "Nothing was imported. Your history limit and auto-delete weren't "
        'changed, because that would delete items. Change them in Settings.',
      );
      // one setting really changed, the other was kept
      expect(
        t(const ImportCounts(settingsApplied: true, limitKept: true)),
        'Imported the settings and ignored apps in this file. Your history '
        "limit wasn't changed, because that would delete items. Change it "
        'in Settings.',
      );
    });

    test('every sentence together, in the order the spec gives', () {
      final m = t(
        const ImportCounts(
          snippetsAdded: 2,
          snippetsAlreadyHere: 1,
          shortcutsDropped: 1,
          historyAdded: 3,
          historyTooOld: 2,
          historyNoRoom: 1,
          limitKept: true,
        ),
      );
      final order = [
        'Imported 2 snippets and 3 history items.',
        '1 snippet was already here.',
        '1 shortcut was already used',
        '2 history items were older',
        "1 history item didn't fit",
        "Your history limit wasn't changed",
      ];
      var at = -1;
      for (final s in order) {
        final i = m.indexOf(s);
        expect(i, greaterThan(at), reason: s);
        at = i;
      }
    });
  });
  group('R8 and R9 in the toast', () {
    Future<void> importTicked(
      WidgetTester tester,
      Map<String, Object?> body, {
      bool tick = true,
    }) async {
      await openFile(tester, body);
      if (tick) {
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
      }
      await tester.tap(hook('import-confirm'));
      await settle(tester);
    }

    Map<String, Object?> clip(String text, String last) => {
      'content': text,
      'kind': 'text',
      'created_at': last,
      'last_copied_at': last,
    };

    String nowIso(Duration ago) => DateTime.now()
        .toUtc()
        .subtract(ago)
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

    testWidgets('nothing added but the settings applied, and a snippet was '
        'already here: the settings sentence, then the skips', (tester) async {
      await show(tester);
      store.snippetStore().insert(
        name: 'A',
        content: 'a',
        type: SnippetType.other,
        nowMs: 1,
      );
      await importTicked(tester, {
        'snippets': [
          {'name': 'A', 'content': 'a', 'type': 'other'},
        ],
        'settings': {'paste_mode': 'copy_only'},
      });
      expect(
        find.text(
          'Imported the settings and ignored apps in this file. 1 snippet '
          'was already here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('something added: the normal sentence, never the settings '
        'one, even with settings applied', (tester) async {
      await show(tester);
      await importTicked(tester, {
        'snippets': [
          {'name': 'B', 'content': 'b', 'type': 'other'},
        ],
        'settings': {'paste_mode': 'copy_only'},
      });
      expect(
        find.text('Imported 1 snippet and 0 history items.'),
        findsOneWidget,
      );
      expect(find.textContaining('Imported the settings'), findsNothing);
    });

    testWidgets('settings in the file but the box not ticked: the normal '
        'sentence, and the history that is already here is counted', (
      tester,
    ) async {
      await show(tester);
      final shown = nowIso(const Duration(hours: 2));
      store.insertOrBump(
        'same',
        ClipKind.text,
        DateTime.now().millisecondsSinceEpoch - 1000,
      );
      await importTicked(tester, {
        'snippets': [
          {'name': 'B', 'content': 'b', 'type': 'other'},
        ],
        'history': [clip('same', shown), clip('fresh', shown)],
        'settings': {'paste_mode': 'copy_only'},
      }, tick: false);
      expect(
        find.text(
          'Imported 1 snippet and 1 history item. 1 history item was already '
          'here.',
        ),
        findsOneWidget,
      );
      expect(store.readSetting('paste_mode'), isNot('copy_only'));
    });

    testWidgets('the confirm count leaves out what is already here, and '
        'the toast agrees with it', (tester) async {
      await show(tester);
      final t1 = DateTime.now().millisecondsSinceEpoch - 5000;
      store.insertOrBump('same', ClipKind.text, t1);
      store.insertOrBump('same 2', ClipKind.text, t1 + 1);
      final shown = nowIso(const Duration(hours: 2));
      await openFile(tester, {
        'snippets': [
          {'name': 'B', 'content': 'b', 'type': 'other'},
        ],
        'history': [
          clip('same', shown),
          clip('same 2', shown),
          clip('fresh 1', shown),
          clip('fresh 2', shown),
          clip('fresh 3', shown),
        ],
      });
      expect(
        find.textContaining('Import 1 snippet and 3 history items?'),
        findsOneWidget,
      );
      await tester.tap(hook('import-confirm'));
      await settle(tester);
      expect(
        find.text(
          'Imported 1 snippet and 3 history items. 2 history items were '
          'already here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a settings-only file imported twice: the first says the '
        'settings were imported, the second says nothing was', (tester) async {
      await show(tester);
      final body = {
        'settings': {'paste_mode': 'copy_only'},
        'ignored_apps': [
          {'app_id': 'com.vault', 'display_name': 'Vault'},
        ],
      };
      await importTicked(tester, body);
      expect(
        find.text('Imported the settings and ignored apps in this file.'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await importTicked(tester, body);
      expect(find.text('Nothing was imported.'), findsOneWidget);
      expect(find.textContaining('Imported the settings'), findsNothing);
    });

    testWidgets(
      'BUG-R10 (Low): when the only thing in the file is a setting that '
      'was kept, nothing was imported, and the toast does not say it was',
      (tester) async {
        await show(tester);
        for (var i = 0; i < 15; i++) {
          store.insertOrBump(
            'item $i',
            ClipKind.text,
            DateTime.now().millisecondsSinceEpoch - 100 + i,
          );
        }
        await importTicked(tester, {
          'settings': {'history_limit': 10},
        });
        expect(store.limit, isNot(10), reason: 'kept: it would delete items');
        expect(find.textContaining('Imported the settings'), findsNothing);
        expect(
          find.textContaining("Your history limit wasn't changed"),
          findsOneWidget,
        );
      },
    );

    test('the sentences come in the lead\'s order, the history "already '
        'here" sentence right after the snippets one', () {
      final m = importedMessage(
        const ImportCounts(
          snippetsAdded: 1,
          snippetsAlreadyHere: 2,
          historyAlreadyHere: 3,
          shortcutsDropped: 1,
          historyAdded: 1,
          historyTooOld: 2,
          historyNoRoom: 1,
          limitKept: true,
        ),
      );
      final order = [
        'Imported 1 snippet and 1 history item.',
        '2 snippets were already here.',
        '3 history items were already here.',
        '1 shortcut was already used',
        '2 history items were older',
        "1 history item didn't fit",
        "Your history limit wasn't changed",
      ];
      var at = -1;
      for (final s in order) {
        final i = m.indexOf(s);
        expect(i, greaterThan(at), reason: '$s in: $m');
        at = i;
      }
      expect(
        importedMessage(const ImportCounts(historyAlreadyHere: 1)),
        'Nothing was imported. 1 history item was already here.',
      );
    });

    test('settingsApplied with nothing added reads as the settings sentence '
        'and keeps every other sentence in order', () {
      final m = importedMessage(
        const ImportCounts(
          settingsApplied: true,
          historyAlreadyHere: 2,
          historyNoRoom: 1,
          expiryKept: true,
        ),
      );
      expect(
        m,
        'Imported the settings and ignored apps in this file. 2 history items '
        "were already here. 1 history item didn't fit under your history "
        "limit and wasn't added. Your auto-delete time wasn't changed, "
        'because that would delete items. Change it in Settings.',
      );
    });
  });
}
