// How typed shortcuts are wired into the app: the ignore list on the same
// encrypted file, the Snippets tab's top slot, and the M1.3 "Copied" toast
// when a typed shortcut could only copy.
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/picker/picker_controller.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../picker/fake_picker_port.dart';
import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

void main() {
  group('openHistory gives the ignore list the same file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_tsw_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<OpenedHistory> open(FakeKeyStore keys) => openHistory(
      keys: keys,
      directory: dir.path,
      log: FakeLog(),
      random: Random(1),
      today: () => DateTime(2026, 11, 8),
    );

    test('a working store: the list is kept in the encrypted file', () async {
      final opened = await open(FakeKeyStore(stored: _key));
      expect(opened.ignoredApps, isA<SqliteIgnoredAppStore>());
      opened.ignoredApps.add(const IgnoredApp('com.example.bank', 'My Bank'));
      opened.store.close();
      final again = await open(FakeKeyStore(stored: _key));
      expect(again.ignoredApps.list().last.appId, 'com.example.bank');
      again.store.close();
    });

    test('memory only: the list is in memory', () async {
      final opened = await open(FakeKeyStore()..readError = 'no keychain');
      expect(opened.ignoredApps, isA<MemoryIgnoredAppStore>());
    });

    test('the history service hands the list on', () {
      final ignored = MemoryIgnoredAppStore();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: FakeLog(),
        ignoredAppStore: ignored,
      );
      addTearDown(h.dispose);
      expect(h.ignoredApps, same(ignored));
    });
  });

  testWidgets('the Snippets tab shows its top slot above the list', (
    tester,
  ) async {
    final service = SnippetService(
      store: MemorySnippetStore(),
      log: FakeLog(),
      editable: true,
      writeClipboard: (_) async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: SnippetsScreen(
          service: service,
          topSlot: const Text('slot', key: ValueKey('slot')),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('slot')), findsOneWidget);
  });

  testWidgets('a typed shortcut that could only copy shows the M1.3 toast', (
    tester,
  ) async {
    final port = FakePickerPort();
    final c = PickerController(
      port: port,
      log: FakeLog(),
      isMac: true,
      toastDuration: const Duration(seconds: 4),
    );
    await c.start();
    c.showCopiedToast();
    expect(c.mode, WindowMode.toast);
    expect(c.toastText, 'Copied — press ⌘V to paste.');
    await tester.pump(const Duration(seconds: 5));
    expect(c.mode, WindowMode.manage);
    c.dispose();
  });
}
