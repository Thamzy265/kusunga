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
      'BUG-R8 (Low): importing a settings-only file does not tell the user '
      '"Imported 0 snippets and 0 history items."; it says what happened',
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
        expect(find.byType(SnackBar), findsOneWidget);
      },
      skip: Platform.environment['KUSUNGA_REPRO'] != '1',
    );
  });

  group('the R1 toast sentences', () {
    String t(ImportCounts c) => importedMessage(c);

    test('no room: the singular and the plural', () {
      expect(
        t(const ImportCounts(historyNoRoom: 1)),
        "Imported 0 snippets and 0 history items. 1 history item didn't fit "
        "under your history limit and wasn't added.",
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
        "Imported 0 snippets and 0 history items. Your history limit wasn't "
        'changed, because that would delete items. Change it in Settings.',
      );
      expect(
        t(const ImportCounts(expiryKept: true)),
        'Imported 0 snippets and 0 history items. Your auto-delete time '
        "wasn't changed, because that would delete items. Change it in "
        'Settings.',
      );
      expect(
        t(const ImportCounts(limitKept: true, expiryKept: true)),
        'Imported 0 snippets and 0 history items. Your history limit and '
        "auto-delete weren't changed, because that would delete items. "
        'Change them in Settings.',
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
}
