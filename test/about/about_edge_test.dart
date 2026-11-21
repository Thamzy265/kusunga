// M1.9a tester: the About section's edge cases, the own-copy rule, keyboard
// paths and the licence page at narrow and wide widths
// (docs/ui/about-and-licences.md).
import 'dart:io';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/build_info.dart';
import 'package:kusunga/about/licences.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/settings/ui/your_data_section.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const release = BuildInfo(version: '0.9.0', build: '1', development: false);
const _repo = 'https://github.com/Thamzy265/kusunga';

void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  Future<void> show(
    WidgetTester tester, {
    BuildInfo info = release,
    Size size = const Size(800, 900),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    bool withYourData = false,
    bool reduceMotion = true,
  }) async {
    source = FakeClipboardSource();
    service = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: SettingsScreen(
          service: service,
          onShowPrivacy: () {},
          buildInfo: info,
          yourData: withYourData
              ? YourDataSetup(
                  files: FakeFilePort(),
                  log: FakeLog(),
                  // Never built: nothing here presses Delete everything.
                  eraser: () => throw UnimplementedError(),
                  quit: () async {},
                )
              : null,
        ),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );
  Finder button(String id) =>
      find.descendant(of: hook(id), matching: find.byType(OutlinedButton));

  Future<void> tapHook(WidgetTester tester, String id) async {
    await tester.ensureVisible(hook(id));
    await tester.tap(hook(id));
    await tester.pump();
    await tester.pump();
  }

  bool hasFocus(WidgetTester tester, Finder f) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final target = tester.element(f);
    var inside = identical(context, target);
    context.visitAncestorElements((e) {
      if (identical(e, target)) inside = true;
      return !inside;
    });
    return inside;
  }

  Future<void> tabTo(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    for (var i = 0; i < 40 && !hasFocus(tester, f); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(hasFocus(tester, f), isTrue, reason: 'could not Tab to $f');
  }

  group('own copies never become history items', () {
    testWidgets('both buttons leave history empty and use only writeOwn', (
      tester,
    ) async {
      final platformWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            platformWrites.add('${(call.arguments as Map)['text']}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester);
      await tapHook(tester, 'about-copy-version');
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await tapHook(tester, 'about-copy-link');
      expect(source.ownWrites, [
        'Kusunga 0.9.0 (build 1)',
        '$_repo/tree/v0.9.0',
      ]);
      expect(
        platformWrites,
        isEmpty,
        reason:
            'Clipboard.setData is not an own copy: the watcher would see it',
      );
      expect(service.items, isEmpty);
    });

    testWidgets('a failed own copy adds nothing either', (tester) async {
      await show(tester);
      source.writeOwnAnswer = false;
      await tapHook(tester, 'about-copy-version');
      expect(service.items, isEmpty);
    });

    test('copyOwn answers false when the platform write throws', () async {
      final s = FakeClipboardSource()..throwOnWrite = true;
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: s,
        log: FakeLog(),
      );
      addTearDown(h.dispose);
      expect(await h.copyOwn('x'), isFalse);
    });

    test('copyOwn passes the text through byte for byte', () async {
      final s = FakeClipboardSource();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: s,
        log: FakeLog(),
      );
      addTearDown(h.dispose);
      const odd = 'Kusunga 0.9.0-β (build 1) — development build\n';
      expect(await h.copyOwn(odd), isTrue);
      expect(s.ownWrites, [odd]);
    });
  });

  group('copy text', () {
    testWidgets('development build copies the whole line with its note', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '0.9.0', build: '1', development: true),
      );
      await tapHook(tester, 'about-copy-version');
      expect(source.ownWrites, ['Kusunga 0.9.0 (build 1) — development build']);
    });

    testWidgets('development build: the link copied is the plain repo', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '0.9.0', build: '1', development: true),
      );
      await tapHook(tester, 'about-copy-link');
      expect(source.ownWrites, [_repo]);
    });

    testWidgets('failed copies in a development build show the error toast', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '', build: '', development: true),
      );
      source.writeOwnAnswer = false;
      await tapHook(tester, 'about-copy-version');
      expect(find.text("Couldn't copy. Try again."), findsOneWidget);
      expect(find.text('Version copied'), findsNothing);
    });

    testWidgets('a success after a failure shows the success toast', (
      tester,
    ) async {
      await show(tester);
      source.writeOwnAnswer = false;
      await tapHook(tester, 'about-copy-link');
      await tester.pumpAndSettle(const Duration(seconds: 4));
      source.writeOwnAnswer = true;
      await tapHook(tester, 'about-copy-link');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Link copied'), findsOneWidget);
      expect(find.text("Couldn't copy. Try again."), findsNothing);
    });
  });

  group('states with odd build info', () {
    testWidgets('version set, build empty: "Kusunga 0.9.0" and its labels', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '0.9.0', build: '', development: false),
      );
      expect(find.text('Kusunga 0.9.0'), findsOneWidget);
      expect(find.textContaining('(build'), findsNothing);
      expect(find.bySemanticsLabel('Copy version 0.9.0'), findsOneWidget);
      await tapHook(tester, 'about-copy-version');
      expect(source.ownWrites, ['Kusunga 0.9.0']);
    });

    testWidgets('only a build set: unknown version, plain link, no tag', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '', build: '7', development: false),
      );
      expect(find.text('Kusunga (version unknown)'), findsOneWidget);
      expect(find.textContaining('/tree/'), findsNothing);
      expect(find.bySemanticsLabel('Copy version'), findsOneWidget);
    });

    testWidgets('unknown version in a development build shows both notes', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '', build: '', development: true),
      );
      expect(
        find.text('Kusunga (version unknown) — development build'),
        findsOneWidget,
      );
      expect(find.text('Development build'), findsOneWidget);
    });

    testWidgets('licence page of an unknown version has no version text', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '', build: '', development: false),
      );
      await tapHook(tester, 'about-view-licences');
      await tester.pumpAndSettle();
      expect(
        tester.widget<LicensePage>(find.byType(LicensePage)).applicationVersion,
        isNull,
      );
    });

    testWidgets('a very long version wraps at 320 px and 200% text', (
      tester,
    ) async {
      final v = '1.2.3-${'x' * 180}';
      await show(
        tester,
        info: BuildInfo(version: v, build: '1', development: false),
        size: const Size(320, 700),
        textScale: 2,
      );
      for (final f in [
        find.textContaining('Kusunga $v'),
        find.textContaining('Source code:'),
      ]) {
        await tester.ensureVisible(f);
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(320));
      }
      expect(tester.takeException(), isNull);
      await tapHook(tester, 'about-copy-version');
      expect(source.ownWrites.single, contains(v));
    });

    testWidgets('dark theme at 320 px and 200% text: no overflow', (
      tester,
    ) async {
      await show(
        tester,
        brightness: Brightness.dark,
        size: const Size(320, 700),
        textScale: 2,
      );
      for (final id in [
        'about-copy-version',
        'about-copy-link',
        'about-view-licences',
      ]) {
        await tester.ensureVisible(hook(id));
        final r = tester.getRect(button(id));
        expect(r.left, greaterThanOrEqualTo(0), reason: id);
        expect(r.right, lessThanOrEqualTo(320), reason: id);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the section comes after Your data', (tester) async {
      await show(tester, withYourData: true);
      final about = tester.getTopLeft(find.text('About')).dy;
      final data = tester.getTopLeft(find.text('Your data')).dy;
      expect(about, greaterThan(data));
    });
  });

  group('keyboard', () {
    testWidgets('Enter and Space on Copy version copy; focus stays put', (
      tester,
    ) async {
      await show(tester);
      await tabTo(tester, button('about-copy-version'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(source.ownWrites, hasLength(1));
      expect(find.text('Version copied'), findsOneWidget);
      // The toast does not take the focus.
      expect(hasFocus(tester, button('about-copy-version')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(source.ownWrites, hasLength(2));
    });

    testWidgets('Tab goes Copy version, Copy link, View licences in order', (
      tester,
    ) async {
      await show(tester);
      final seen = <String>[];
      await tabTo(tester, button('about-copy-version'));
      seen.add('v');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (hasFocus(tester, button('about-copy-link'))) seen.add('l');
      // The selectable link text may take a stop; allow one.
      if (seen.length == 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (hasFocus(tester, button('about-copy-link'))) seen.add('l');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (hasFocus(tester, button('about-view-licences'))) seen.add('x');
      expect(seen, ['v', 'l', 'x']);
    });

    testWidgets('Esc on Settings does nothing and does not crash', (
      tester,
    ) async {
      await show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('About'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('licence page', () {
    setUp(() {
      LicenseRegistry.reset();
      registerLicences(bundle: _FileBundle());
    });
    tearDown(LicenseRegistry.reset);

    Future<void> open(WidgetTester tester, Size size) async {
      await show(tester, size: size);
      await tapHook(tester, 'about-view-licences');
      await tester.pumpAndSettle();
    }

    for (final width in [320.0, 600.0, 900.0]) {
      testWidgets('lists the three notices at ${width.toInt()} px', (
        tester,
      ) async {
        await open(tester, Size(width, 800));
        expect(find.byType(LicensePage), findsOneWidget);
        for (final name in ['Kusunga', 'SQLite3 Multiple Ciphers', 'SQLite']) {
          expect(find.text(name), findsWidgets, reason: name);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('at 320 px and 200% text it still builds, no overflow', (
      tester,
    ) async {
      await show(tester, size: const Size(320, 700), textScale: 2);
      await tapHook(tester, 'about-view-licences');
      // Flutter's own spinner view (the moment the notices load, under 1 s)
      // is a Column that is taller than 700 px at 200% text. It is not
      // Kusunga's layout, and the old slide-in hid it by keeping the page
      // off-stage until the list had loaded; with no transition (reduced
      // motion) it is painted once. Only the loaded page is checked.
      tester.takeException();
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme: the page builds, no overflow', (tester) async {
      await show(
        tester,
        brightness: Brightness.dark,
        size: const Size(900, 800),
      );
      await tapHook(tester, 'about-view-licences');
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking SQLite shows the blessing; Back returns to the list', (
      tester,
    ) async {
      await open(tester, const Size(320, 800));
      await tester.tap(find.text('SQLite').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('May you do good and not evil'),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('Kusunga'), findsWidgets);
    });

    testWidgets('at 320 px, one Esc on a notice goes to the list, the next to '
        'Settings with focus on View licences', (tester) async {
      await show(tester, size: const Size(320, 800));
      await tabTo(tester, button('about-view-licences'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SQLite').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('May you do good and not evil'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Detail to list: still on the licences page, text gone.
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.textContaining('May you do good and not evil'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Kusunga'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(find.text('About'), findsOneWidget);
      expect(hasFocus(tester, button('about-view-licences')), isTrue);
    });

    testWidgets('Esc after moving focus on the page still goes back', (
      tester,
    ) async {
      await open(tester, const Size(900, 800));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('Esc returns the focus to View licences', (tester) async {
      await show(tester);
      await tabTo(tester, button('about-view-licences'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(hasFocus(tester, button('about-view-licences')), isTrue);
    });

    testWidgets('open, Esc, open again works every time', (tester) async {
      await show(tester);
      for (var i = 0; i < 3; i++) {
        await tapHook(tester, 'about-view-licences');
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget, reason: 'round $i');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsNothing, reason: 'round $i');
      }
    });

    // Spec: "Kusunga, SQLite3 Multiple Ciphers and SQLite at the top, then
    // Flutter's collected notices". Flutter's page pins only the first package
    // of the first collector and sorts every other package by its lower-cased
    // name, so Kusunga must come from the FIRST collector. KusungaBinding
    // registers ours before the binding's own NOTICES collector, which is the
    // order modelled here (binding_order_test.dart proves it with the real
    // binding). A pinned "abseil-cpp" would put Kusunga in the middle.
    testWidgets(
      'Kusunga is the first row, above the packages Flutter collects',
      (tester) async {
        LicenseRegistry.addLicense(
          () => Stream.fromIterable([
            LicenseEntryWithLineBreaks(['abseil-cpp'], 'text'),
            LicenseEntryWithLineBreaks(['archive', 'zlib'], 'text'),
            LicenseEntryWithLineBreaks(['path'], 'text'),
            LicenseEntryWithLineBreaks(['sqlite3'], 'text'),
          ]),
        );
        await open(tester, const Size(900, 3000));
        final rows = [
          for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
            (t.title! as Text).data!,
        ];
        expect(rows.first, 'Kusunga');
        expect(rows, containsAll(['abseil-cpp', 'archive', 'path', 'sqlite3']));
        expect(rows.indexOf('abseil-cpp'), greaterThan(0));
      },
    );

    // Flutter's list sorts "SQLite" and "SQLite3 Multiple Ciphers" in among
    // the pub packages, so the Kusunga row also leads to both notices.
    testWidgets('both SQLite notices are reachable from the Kusunga row', (
      tester,
    ) async {
      LicenseRegistry.addLicense(
        () => Stream.value(LicenseEntryWithLineBreaks(['abseil-cpp'], 'text')),
      );
      await open(tester, const Size(320, 800));
      await tester.tap(find.widgetWithText(ListTile, 'Kusunga'));
      await tester.pumpAndSettle();
      for (final text in [
        'SQLite3 Multiple Ciphers 2.5.0 and the parts it bundles',
        'May you do good and not evil',
      ]) {
        await tester.scrollUntilVisible(
          find.textContaining(text),
          1500,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 200,
        );
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
    });

    // Spec: "Focus moves to the first row" once the list has loaded.
    for (final width in [320.0, 900.0]) {
      testWidgets('focus moves to the first row, at ${width.toInt()} px', (
        tester,
      ) async {
        await open(tester, Size(width, 800));
        expect(
          hasFocus(tester, find.widgetWithText(ListTile, 'Kusunga')),
          isTrue,
        );
      });
    }

    // Esc after the focus has moved to the first row still goes back.
    testWidgets('Esc on the first row goes back to Settings', (tester) async {
      await open(tester, const Size(320, 800));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(find.text('About'), findsOneWidget);
    });

    // Spec: "the page transition follows the existing reduced-motion
    // handling" (history_row.dart, picker_panel.dart).
    group('page transition', () {
      Future<ModalRoute<void>> openRoute(
        WidgetTester tester, {
        required bool reduceMotion,
      }) async {
        await show(tester, reduceMotion: reduceMotion);
        await tapHook(tester, 'about-view-licences');
        return ModalRoute.of(tester.element(find.byType(LicensePage)))!
            as ModalRoute<void>;
      }

      testWidgets('reduced motion: the page is fully in place at once', (
        tester,
      ) async {
        final route = await openRoute(tester, reduceMotion: true);
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
        expect(route.animation!.status, AnimationStatus.completed);
      });

      testWidgets('normal motion: the page slides in over time', (
        tester,
      ) async {
        final route = await openRoute(tester, reduceMotion: false);
        expect(route.transitionDuration, greaterThan(Duration.zero));
        expect(route.animation!.status, isNot(AnimationStatus.completed));
        await tester.pumpAndSettle();
        expect(route.animation!.status, AnimationStatus.completed);
      });
    });

    testWidgets('one notice that fails to load does not blank the whole page', (
      tester,
    ) async {
      LicenseRegistry.reset();
      registerLicences(bundle: _BrokenBundle());
      await show(tester);
      await tapHook(tester, 'about-view-licences');
      await tester.pumpAndSettle();
      // Kusunga was yielded before the failing asset: it must still show.
      expect(find.text('Kusunga'), findsWidgets);
    });
  });
}

/// The bundled files, read from the project folder (the real rootBundle does
/// real file IO, which never finishes under a widget test's fake clock).
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// Loads LICENSE and the SQLite3 Multiple Ciphers notice, but not sqlite.txt.
class _BrokenBundle extends _FileBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == sqliteNoticeAsset) throw FlutterError('asset missing');
    return super.load(key);
  }
}
