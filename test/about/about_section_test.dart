// M1.9a UI spec (docs/ui/about-and-licences.md): the About section at the
// bottom of Settings, its states, breakpoints and accessibility notes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/build_info.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const release = BuildInfo(version: '0.9.0', build: '1', development: false);
const _repo = 'https://github.com/Thamzy265/kusunga';
const _gpl =
    'Kusunga is free software under the GNU General Public License, '
    'version 3 only. It comes with NO WARRANTY.';

/// The focused element is [f] or inside it.
bool _hasFocus(WidgetTester tester, Finder f) {
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

void main() {
  late FakeClipboardSource source;
  late HistoryService service;

  Future<void> show(
    WidgetTester tester, {
    BuildInfo info = release,
    Size size = const Size(800, 900),
    double textScale = 1,
    Brightness brightness = Brightness.light,
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
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: SettingsScreen(
          service: service,
          onShowPrivacy: () {},
          buildInfo: info,
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

  group('default', () {
    testWidgets('heading, version line, copyright, GPL sentence, link', (
      tester,
    ) async {
      await show(tester);
      for (final text in [
        'About',
        'Kusunga 0.9.0 (build 1)',
        'Copyright (C) 2026 William Nasoni',
        _gpl,
        '$_repo/tree/v0.9.0',
        'Copy version',
        'Copy link',
        'View licences',
      ]) {
        await tester.ensureVisible(find.textContaining(text).first);
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
      expect(find.text('Source code: '), findsNothing);
      expect(find.textContaining('Source code:'), findsOneWidget);
      expect(find.text('Development build'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('About is a heading and comes last, after the other sections', (
      tester,
    ) async {
      await show(tester);
      final about = tester.getTopLeft(find.text('About')).dy;
      expect(about, greaterThan(tester.getTopLeft(find.text('History')).dy));
      expect(
        tester.getSemantics(find.text('About')),
        matchesSemantics(isHeader: true, label: 'About'),
      );
    });
  });

  group('copy buttons', () {
    testWidgets('Copy version: own copy of the version line, toast', (
      tester,
    ) async {
      await show(tester);
      await tapHook(tester, 'about-copy-version');
      expect(source.ownWrites, ['Kusunga 0.9.0 (build 1)']);
      expect(find.text('Version copied'), findsOneWidget);
    });

    testWidgets('Copy link: own copy of the source link, toast', (
      tester,
    ) async {
      await show(tester);
      await tapHook(tester, 'about-copy-link');
      expect(source.ownWrites, ['$_repo/tree/v0.9.0']);
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('a failed copy says so and does not claim success', (
      tester,
    ) async {
      await show(tester);
      source.writeOwnAnswer = false;
      await tapHook(tester, 'about-copy-version');
      expect(find.text("Couldn't copy. Try again."), findsOneWidget);
      expect(find.text('Version copied'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tapHook(tester, 'about-copy-link');
      expect(find.text("Couldn't copy. Try again."), findsOneWidget);
      expect(find.text('Link copied'), findsNothing);
    });

    testWidgets('a copy that throws says so too', (tester) async {
      await show(tester);
      source.throwOnWrite = true;
      await tapHook(tester, 'about-copy-link');
      expect(find.text("Couldn't copy. Try again."), findsOneWidget);
    });

    testWidgets('the copies carry only the version or the link', (
      tester,
    ) async {
      await show(tester);
      await tapHook(tester, 'about-copy-version');
      await tapHook(tester, 'about-copy-link');
      expect(source.ownWrites, hasLength(2));
      for (final w in source.ownWrites) {
        expect(w, anyOf(startsWith('Kusunga '), startsWith('https://')));
      }
    });
  });

  group('build states', () {
    testWidgets('development build: note, plain link, caption', (tester) async {
      await show(
        tester,
        info: const BuildInfo(version: '0.9.0', build: '1', development: true),
      );
      expect(
        find.text('Kusunga 0.9.0 (build 1) — development build'),
        findsOneWidget,
      );
      expect(find.textContaining('Source code: $_repo'), findsOneWidget);
      expect(find.textContaining('/tree/'), findsNothing);
      expect(find.text('Development build'), findsOneWidget);
    });

    testWidgets('version unknown: the fallback line, and it is copied', (
      tester,
    ) async {
      await show(
        tester,
        info: const BuildInfo(version: '', build: '', development: false),
      );
      expect(find.text('Kusunga (version unknown)'), findsOneWidget);
      await tapHook(tester, 'about-copy-version');
      expect(source.ownWrites, ['Kusunga (version unknown)']);
    });
  });

  group('licences', () {
    testWidgets('View licences opens the licence page, Esc comes back', (
      tester,
    ) async {
      await show(tester);
      await tapHook(tester, 'about-view-licences');
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      final page = tester.widget<LicensePage>(find.byType(LicensePage));
      expect(page.applicationName, 'Kusunga');
      expect(page.applicationVersion, '0.9.0 (build 1)');
      expect(
        page.applicationLegalese,
        'Copyright (C) 2026 William Nasoni. Licensed under the GNU GPL, '
        'version 3 only. This program comes with ABSOLUTELY NO WARRANTY. '
        'This is free software, and you are welcome to redistribute it under '
        'certain conditions; see the GNU GPL for details.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('Back returns the focus to View licences', (tester) async {
      await show(tester);
      final button = find.descendant(
        of: hook('about-view-licences'),
        matching: find.byType(OutlinedButton),
      );
      await tester.ensureVisible(button);
      // Keyboard use: Tab until View licences has the focus.
      for (var i = 0; i < 30 && !_hasFocus(tester, button); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(_hasFocus(tester, button), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(_hasFocus(tester, button), isTrue);
    });
  });

  group('accessibility', () {
    testWidgets('buttons say what they copy', (tester) async {
      await show(tester);
      expect(
        find.bySemanticsLabel('Copy version 0.9.0 build 1'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Copy source code link'), findsOneWidget);
      expect(find.bySemanticsLabel('View licences'), findsOneWidget);
    });

    testWidgets('the link text is selectable', (tester) async {
      await show(tester);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('Tab order: Copy version, Copy link, View licences', (
      tester,
    ) async {
      await show(tester);
      final names = <String>[];
      for (final id in [
        'about-copy-version',
        'about-copy-link',
        'about-view-licences',
      ]) {
        await tester.ensureVisible(hook(id));
        final y = tester
            .getTopLeft(
              find.descendant(
                of: hook(id),
                matching: find.byType(OutlinedButton),
              ),
            )
            .dy;
        names.add('$y');
      }
      final ys = names.map(double.parse).toList();
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('targets are at least 24 x 24', (tester) async {
      await show(tester);
      for (final id in [
        'about-copy-version',
        'about-copy-link',
        'about-view-licences',
      ]) {
        final size = tester.getSize(
          find.descendant(of: hook(id), matching: find.byType(OutlinedButton)),
        );
        expect(size.width, greaterThanOrEqualTo(24), reason: id);
        expect(size.height, greaterThanOrEqualTo(24), reason: id);
      }
    });

    testWidgets('dark theme builds without overflow', (tester) async {
      await show(tester, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('About'), findsOneWidget);
    });
  });

  group('breakpoints', () {
    Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);
    Finder button(String id) =>
        find.descendant(of: hook(id), matching: find.byType(OutlinedButton));

    testWidgets('600 px and wider: buttons at the end of their lines', (
      tester,
    ) async {
      await show(tester, size: const Size(800, 900));
      final line = find.text('Kusunga 0.9.0 (build 1)');
      await tester.ensureVisible(line);
      final b = rect(tester, button('about-copy-version'));
      expect(b.center.dy, closeTo(rect(tester, line).center.dy, 12));
      expect(b.left, greaterThan(rect(tester, line).right));
    });

    testWidgets('360 px: Copy version sits under its line', (tester) async {
      await show(tester, size: const Size(360, 900));
      final line = find.text('Kusunga 0.9.0 (build 1)');
      await tester.ensureVisible(line);
      expect(
        rect(tester, button('about-copy-version')).top,
        greaterThanOrEqualTo(rect(tester, line).bottom),
      );
      final licences = rect(tester, button('about-view-licences'));
      expect(
        licences.top,
        greaterThan(rect(tester, button('about-copy-link')).bottom),
      );
    });

    for (final (size, scale) in [
      (const Size(320, 700), 1.0),
      (const Size(360, 700), 2.0),
    ]) {
      testWidgets('${size.width} px at ${scale}x text: no overflow, stacked', (
        tester,
      ) async {
        await show(tester, size: size, textScale: scale);
        for (final id in [
          'about-copy-version',
          'about-copy-link',
          'about-view-licences',
        ]) {
          await tester.ensureVisible(hook(id));
          final r = rect(tester, button(id));
          expect(r.left, greaterThanOrEqualTo(0), reason: id);
          expect(r.right, lessThanOrEqualTo(size.width), reason: id);
        }
        final link = find.textContaining('Source code:');
        await tester.ensureVisible(link);
        expect(rect(tester, link).right, lessThanOrEqualTo(size.width));
        expect(
          rect(tester, button('about-copy-link')).top,
          greaterThanOrEqualTo(rect(tester, link).bottom),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
