// F1: each mode in which snippets can't be opened has its own banner text
// (docs/ui/saved-snippets.md, Copy, "Banners"), on the Snippets tab and,
// for the safety copy, on the History tab too.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/migrations.dart';
import 'package:kusunga/history/ui/history_screen.dart';
import 'package:kusunga/snippets/ui/snippets_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

const keychainText =
    "Snippets can't be opened right now, because Kusunga can't reach your "
    'keychain.';
const newerText =
    'Your snippets were saved by a newer version of Kusunga. Update Kusunga '
    'to see them.';
const updateFailedText =
    "Kusunga couldn't update your saved data, so nothing was changed. Quit "
    'and reopen Kusunga to try again.';
const safetyCopyText =
    "Kusunga couldn't make a safety copy of your data, so nothing was "
    'changed. Free up some disk space, then quit and reopen Kusunga.';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kusunga_banners_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<HistoryService> openService(
    FakeKeyStore keys, {
    List<Migration> migrations = kMigrations,
  }) async {
    final opened = await openHistory(
      keys: keys,
      directory: dir.path,
      log: FakeLog(),
      random: Random(1),
      today: () => DateTime(2026, 11, 4),
      migrations: migrations,
    );
    final s = HistoryService(
      store: opened.store,
      notices: opened.notices,
      snippetStore: opened.snippets,
      snippetsUnavailable: opened.snippetsUnavailable,
      source: FakeClipboardSource(),
      log: FakeLog(),
    )..start();
    addTearDown(s.close);
    return s;
  }

  Future<void> writeV2() async {
    final v2 = await openHistory(
      keys: FakeKeyStore(stored: _key),
      directory: dir.path,
      log: FakeLog(),
      migrations: kMigrations.sublist(0, 2),
    );
    v2.store.close();
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: KusungaTokens.themeData(Brightness.light), home: home),
    );
    await tester.pump();
  }

  Future<void> expectSnippetsBanner(
    WidgetTester tester,
    HistoryService s,
    String text,
  ) async {
    await show(tester, SnippetsScreen(service: s.snippets));
    expect(find.text(text), findsOneWidget);
    for (final other in [
      keychainText,
      newerText,
      updateFailedText,
      safetyCopyText,
    ]) {
      if (other != text) expect(find.text(other), findsNothing);
    }
    expect(find.textContaining('still paste'), findsNothing);
    expect(s.snippets.canEdit, isFalse);
    expect(s.snippets.items, isEmpty);
  }

  testWidgets('keychain unreachable', (tester) async {
    final s = await tester.runAsync(
      () => openService(FakeKeyStore()..readError = 'no keychain'),
    );
    await expectSnippetsBanner(tester, s!, keychainText);
  });

  testWidgets('a newer file', (tester) async {
    final s = await tester.runAsync(() async {
      final newer = await openHistory(
        keys: FakeKeyStore(stored: _key),
        directory: dir.path,
        log: FakeLog(),
        migrations: [
          ...kMigrations,
          const Migration(version: 5, statements: []),
        ],
      );
      newer.store.close();
      return openService(FakeKeyStore(stored: _key));
    });
    await expectSnippetsBanner(tester, s!, newerText);
  });

  testWidgets('the update (migration) failed', (tester) async {
    final s = await tester.runAsync(() async {
      await writeV2();
      return openService(
        FakeKeyStore(stored: _key),
        migrations: [
          ...kMigrations.sublist(0, 2),
          const Migration(version: 3, statements: ['NOT SQL']),
        ],
      );
    });
    await expectSnippetsBanner(tester, s!, updateFailedText);
  });

  testWidgets('the safety copy could not be made: both tabs say so, and '
      'History no longer says "until you update"', (tester) async {
    final s = await tester.runAsync(() async {
      await writeV2();
      Directory('${dir.path}/kusunga.db.bak').createSync();
      return openService(FakeKeyStore(stored: _key));
    });
    expect(s!.banners, {HistoryBanner.backupFailed});
    await expectSnippetsBanner(tester, s, safetyCopyText);
    await show(tester, HistoryScreen(service: s));
    expect(find.text(safetyCopyText), findsOneWidget);
    expect(find.textContaining('until you update'), findsNothing);
  });
}
