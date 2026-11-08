import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/app.dart';
import 'package:kusunga/history/data_profile.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/open_app_history.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:path/path.dart' as p;

import '../../snippets/snippet_service_test.dart' show FlakySnippetStore;
import '../../support/fakes.dart';

/// Tester round 8 on f2c100f and 3ed1ba8 (QA-M14-6): the memory-only banners
/// name a rejected test-profile switch, not the keychain, in Debug builds. Every
/// banner and every profile state is checked, through the same wiring as
/// main(): `dataProfileFrom` -> `dataProfileSetup` -> `openAppHistory` ->
/// `KusungaApp(dataProfileRejected: profile is RejectedDataProfile)`.
void main() {
  const historySwitch =
      "History won't be kept after you quit, because the test profile switch "
      "wasn't recognised.";
  const historyKeychain =
      "History won't be kept after you quit, because Kusunga can't reach "
      'your keychain.';
  const snippetsSwitch =
      "Snippets can't be opened right now, because the test profile switch "
      "wasn't recognised.";
  const snippetsKeychain =
      "Snippets can't be opened right now, because Kusunga can't reach "
      'your keychain.';
  const hex =
      '00112233445566778899aabbccddeeff'
      '00112233445566778899aabbccddeeff';

  Future<void> setSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Every string drawn by a Text widget.
  Set<String> texts(WidgetTester tester) => {
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      if (w.data != null) w.data!,
  };

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> openSnippetsTab(WidgetTester tester) async {
    await tester.tap(hook('main-tab-snippets'));
    await tester.pump();
    await tester.pump();
  }

  group('every banner with and without a rejected switch', () {
    HistoryService make(
      Set<HistoryNotice> notices, {
      SnippetsUnavailable? reason,
      FlakySnippetStore? store,
    }) => HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      notices: notices,
      snippetStore: store ?? MemorySnippetStore(),
      snippetsUnavailable: reason,
    )..start();

    Future<Set<String>> historyTexts(
      WidgetTester tester,
      HistoryService s, {
      required bool rejected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          home: HistoryHost(
            history: Future.value(s),
            dataProfileRejected: rejected,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return texts(tester);
    }

    for (final notices in <Set<HistoryNotice>>[
      {},
      {HistoryNotice.readError},
      {HistoryNotice.incompatible},
      {HistoryNotice.backupFailed},
      {HistoryNotice.readError, HistoryNotice.backupFailed},
    ]) {
      testWidgets('History, notices ${notices.map((n) => n.name)}: a '
          'rejected switch changes nothing (no memory-only banner)', (
        tester,
      ) async {
        await setSize(tester);
        final s = make(notices);
        addTearDown(s.dispose);
        final off = await historyTexts(tester, s, rejected: false);
        await tester.pumpWidget(const SizedBox());
        final s2 = make(notices);
        addTearDown(s2.dispose);
        final on = await historyTexts(tester, s2, rejected: true);
        expect(on, off);
        expect(on, isNot(contains(historySwitch)));
      });
    }

    testWidgets('History, memoryOnly together with other notices: the '
        'memory-only line names the switch, the others keep their text', (
      tester,
    ) async {
      await setSize(tester);
      final notices = {HistoryNotice.memoryOnly, HistoryNotice.readError};
      final s = make(notices);
      addTearDown(s.dispose);
      final off = await historyTexts(tester, s, rejected: false);
      await tester.pumpWidget(const SizedBox());
      final s2 = make(notices);
      addTearDown(s2.dispose);
      final on = await historyTexts(tester, s2, rejected: true);
      expect(off, contains(historyKeychain));
      expect(on, contains(historySwitch));
      expect(on, isNot(contains(historyKeychain)));
      expect(on.difference({historySwitch}), off.difference({historyKeychain}));
    });

    for (final (reason, notices) in <(SnippetsUnavailable, Set<HistoryNotice>)>[
      (SnippetsUnavailable.newerFile, {HistoryNotice.incompatible}),
      (SnippetsUnavailable.backupFailed, {HistoryNotice.backupFailed}),
      (SnippetsUnavailable.updateFailed, {HistoryNotice.incompatible}),
    ]) {
      testWidgets('Snippets banner "${reason.name}": a rejected switch '
          'keeps its own text', (tester) async {
        await setSize(tester);
        final s = make(notices, reason: reason);
        addTearDown(s.dispose);
        await historyTexts(tester, s, rejected: false);
        await openSnippetsTab(tester);
        final off = texts(tester);
        await tester.pumpWidget(const SizedBox());
        final s2 = make(notices, reason: reason);
        addTearDown(s2.dispose);
        await historyTexts(tester, s2, rejected: true);
        await openSnippetsTab(tester);
        final on = texts(tester);
        expect(on, off);
        expect(on, isNot(contains(snippetsSwitch)));
      });
    }

    testWidgets('Snippets banner (keychain reason): the switch text only '
        'when rejected', (tester) async {
      await setSize(tester);
      final s = make({HistoryNotice.memoryOnly});
      addTearDown(s.dispose);
      await historyTexts(tester, s, rejected: false);
      await openSnippetsTab(tester);
      expect(texts(tester), contains(snippetsKeychain));
      await tester.pumpWidget(const SizedBox());
      final s2 = make({HistoryNotice.memoryOnly});
      addTearDown(s2.dispose);
      await historyTexts(tester, s2, rejected: true);
      await openSnippetsTab(tester);
      expect(texts(tester), contains(snippetsSwitch));
      expect(texts(tester), isNot(contains(snippetsKeychain)));
    });

    testWidgets('the Snippets read-error banner ("Try again") is the same '
        'with a rejected switch', (tester) async {
      await setSize(tester);
      final store = FlakySnippetStore()..failReads = true;
      final s = make({}, store: store);
      addTearDown(s.dispose);
      await historyTexts(tester, s, rejected: true);
      await openSnippetsTab(tester);
      expect(
        texts(tester),
        contains("Kusunga couldn't read your snippets. Try again."),
      );
      expect(texts(tester), isNot(contains(snippetsSwitch)));
    });
  });

  group('through the real wiring, every profile state', () {
    late Directory base;
    final services = <HistoryService>[];
    setUp(() => base = Directory.systemTemp.createTempSync('kusunga_banner_'));
    tearDown(() async {
      for (final s in services) {
        await s.close();
        s.dispose();
      }
      services.clear();
      base.deleteSync(recursive: true);
    });

    /// What main() does, with a temp folder and a fake key store.
    Future<void> launch(
      WidgetTester tester,
      List<String> args,
      FakeKeyStore keys, {
      bool debug = true,
    }) async {
      await setSize(tester);
      final profile = dataProfileFrom(args, debug: debug);
      final deferred = DeferredErrorLog(mirror: FakeLog());
      final data = dataProfileSetup(
        profile,
        supportDirectory: () async => base,
        keys: keys,
        log: deferred,
      );
      // Real file I/O: outside the fake-async zone of the widget test.
      final history = (await tester.runAsync(
        () => openAppHistory(
          deferred: deferred,
          supportDirectory: data.supportDirectory,
          keys: data.keys,
          source: FakeClipboardSource(),
        ),
      ))!;
      services.add(history);
      await tester.pumpWidget(
        KusungaApp(
          history: Future.value(history),
          dataProfile: profile is ActiveDataProfile ? profile.name : null,
          dataProfileRejected: profile is RejectedDataProfile,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    for (final args in <List<String>>[
      ['-KusungaDataProfil', 'qa'],
      ['-KusungaDataProfle', 'qa'],
      ['KusungaDataProfile', 'qa'],
      ['–KusungaDataProfile', 'qa'],
      ['-Kusunga', 'DataProfile', 'qa'],
      ['-KusungaDataProfile', 'QA'],
      ['-KusungaDataProfile', ''],
      ['-KusungaDataProfile'],
      ['-KusungaDataProfile', 'qa', '-KusungaDataProfile', 'qb'],
    ]) {
      testWidgets('rejected ${args.join(' ')}: both banners name the '
          'switch', (tester) async {
        await launch(tester, args, FakeKeyStore(stored: hex));
        expect(texts(tester), contains(historySwitch));
        expect(texts(tester), isNot(contains(historyKeychain)));
        await openSnippetsTab(tester);
        expect(texts(tester), contains(snippetsSwitch));
        expect(texts(tester), isNot(contains(snippetsKeychain)));
        expect(find.textContaining('Test profile:'), findsNothing);
      });
    }

    testWidgets('a real keychain failure with no profile: the keychain '
        'text', (tester) async {
      await launch(tester, [], FakeKeyStore()..readError = StateError('x'));
      expect(texts(tester), contains(historyKeychain));
      expect(texts(tester), isNot(contains(historySwitch)));
      await openSnippetsTab(tester);
      expect(texts(tester), contains(snippetsKeychain));
    });

    testWidgets('a good profile with a working key: no banner, and the '
        'Test profile label', (tester) async {
      await launch(tester, [
        '-KusungaDataProfile',
        'qa',
      ], FakeKeyStore(stored: hex));
      expect(texts(tester), isNot(contains(historyKeychain)));
      expect(texts(tester), isNot(contains(historySwitch)));
      expect(find.text('Test profile: qa'), findsOneWidget);
    });

    testWidgets('a good profile with NO key yet (memory only, never writes '
        'a key): the keychain text, as before (the key really is missing)', (
      tester,
    ) async {
      await launch(tester, ['-KusungaDataProfile', 'qa'], FakeKeyStore());
      expect(texts(tester), contains(historyKeychain));
      expect(texts(tester), isNot(contains(historySwitch)));
      expect(find.text('Test profile: qa'), findsOneWidget);
    });

    testWidgets('a good profile whose folder is a link (refused, detail 2): '
        'the keychain text, as before', (tester) async {
      Directory(p.join(base.path, 'profiles')).createSync();
      Link(p.join(base.path, 'profiles', 'qa')).createSync(base.path);
      await launch(tester, [
        '-KusungaDataProfile',
        'qa',
      ], FakeKeyStore(stored: hex));
      expect(texts(tester), contains(historyKeychain));
      expect(texts(tester), isNot(contains(historySwitch)));
    }, skip: Platform.isWindows);

    testWidgets('Release (debug off) with a misspelled switch: no profile, '
        'the real folder opens, no banner, no switch text', (tester) async {
      await launch(
        tester,
        ['-KusungaDataProfil', 'qa'],
        FakeKeyStore(stored: hex),
        debug: false,
      );
      expect(texts(tester), isNot(contains(historySwitch)));
      expect(texts(tester), isNot(contains(historyKeychain)));
      expect(find.textContaining('Test profile'), findsNothing);
    });

    testWidgets('Release with a keychain failure and a misspelled switch: '
        'the keychain text (the switch is ignored)', (tester) async {
      await launch(
        tester,
        ['-KusungaDataProfil', 'qa'],
        FakeKeyStore()..readError = StateError('x'),
        debug: false,
      );
      expect(texts(tester), contains(historyKeychain));
      expect(texts(tester), isNot(contains(historySwitch)));
      await openSnippetsTab(tester);
      expect(texts(tester), contains(snippetsKeychain));
      expect(texts(tester), isNot(contains(snippetsSwitch)));
    });

    testWidgets('the banner never shows the argument, a name or a path', (
      tester,
    ) async {
      await launch(tester, [
        '-KusungaDataProfil',
        'secretname',
      ], FakeKeyStore(stored: hex));
      for (final t in texts(tester)) {
        expect(t.toLowerCase(), isNot(contains('secretname')));
        expect(t, isNot(contains(base.path)));
        expect(t.toLowerCase(), isNot(contains('-kusunga')));
      }
    });
  });
}
