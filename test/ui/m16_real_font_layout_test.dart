// M1.6 tester: the developer moved "600 px: still one row" to 680 px and a
// History text-size test to 520 x 440, because the test font (Ahem) draws
// every letter as wide as the font size. This checks the claim with a real
// proportional font (Roboto from the Flutter SDK, loaded as 'RealRoboto'):
// if the layout really fits at 600 px and at 520 x 400 with a real font, the
// moved tests hide nothing. Skipped when the SDK font files are not found.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

String? _fontDir() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) '$root/bin/cache/artifacts/material_fonts',
    '/Users/williamnasoni/Developer/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final c in candidates) {
    if (File('$c/Roboto-Regular.ttf').existsSync()) return c;
  }
  return null;
}

Future<void> _loadReal() async {
  final dir = _fontDir()!;
  final loader = FontLoader('RealRoboto')
    ..addFont(
      Future.value(
        ByteData.sublistView(File('$dir/Roboto-Regular.ttf').readAsBytesSync()),
      ),
    )
    ..addFont(
      Future.value(
        ByteData.sublistView(File('$dir/Roboto-Bold.ttf').readAsBytesSync()),
      ),
    );
  await loader.load();
}

void main() {
  final skip = _fontDir() == null
      ? 'Roboto not found in the Flutter SDK'
      : null;

  Future<void> show(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    bool real = true,
    String tabHook = 'main-tab-snippets',
  }) async {
    final service = HistoryService(
      store: MemoryHistoryStore(),
      source: FakeClipboardSource(),
      log: FakeLog(),
      snippetStore: MemorySnippetStore(),
    )..start();
    addTearDown(service.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var theme = KusungaTokens.themeData(Brightness.light);
    if (real) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'RealRoboto'),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: HistoryHost(history: Future.value(service)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier(tabHook));
    await tester.pump();
  }

  Rect tab(WidgetTester tester, String name) =>
      tester.getRect(find.bySemanticsIdentifier('main-tab-$name'));

  group('real proportional font', () {
    setUpAll(() async {
      if (skip == null) await _loadReal();
    });

    testWidgets('600 px: History, Snippets, Privacy, Settings (M1.7) and New '
        'snippet on one row (the test the developer moved to 680 px)', (
      tester,
    ) async {
      await show(tester, const Size(600, 632));
      final h = tab(tester, 'history');
      final s = tab(tester, 'snippets');
      final p = tab(tester, 'privacy');
      final g = tab(tester, 'settings');
      final n = tester.getRect(find.bySemanticsIdentifier('snippet-new'));
      expect(s.center.dy, moreOrLessEquals(h.center.dy, epsilon: 1));
      expect(p.center.dy, moreOrLessEquals(h.center.dy, epsilon: 1));
      expect(g.center.dy, moreOrLessEquals(h.center.dy, epsilon: 1));
      expect(n.center.dy, moreOrLessEquals(h.center.dy, epsilon: 12));
      expect(g.right, lessThan(n.left));
      expect(tester.takeException(), isNull);
    }, skip: skip != null);

    testWidgets('520 px at 200% text: the tabs stay on one row (the claim '
        'behind moving the History test to 440 px high)', (tester) async {
      await show(
        tester,
        const Size(520, 400),
        scale: 2,
        tabHook: 'main-tab-history',
      );
      final h = tab(tester, 'history');
      final s = tab(tester, 'snippets');
      final p = tab(tester, 'privacy');
      expect(s.center.dy, moreOrLessEquals(h.center.dy, epsilon: 1));
      expect(p.center.dy, moreOrLessEquals(h.center.dy, epsilon: 1));
      expect(tester.takeException(), isNull);
    }, skip: skip != null);

    testWidgets('360 px at 200% text: three tabs wrap, nothing overflows, '
        'every tab is reachable inside the window', (tester) async {
      await show(
        tester,
        const Size(360, 640),
        scale: 2,
        tabHook: 'main-tab-privacy',
      );
      for (final n in ['history', 'snippets', 'privacy']) {
        final r = tab(tester, n);
        expect(r.left, greaterThanOrEqualTo(0), reason: n);
        expect(r.right, lessThanOrEqualTo(360), reason: n);
      }
      expect(tester.takeException(), isNull);
    }, skip: skip != null);

    testWidgets('control: with the Ahem test font the same 600 px does not '
        'fit on one row, so the real font is really in use above', (
      tester,
    ) async {
      await show(tester, const Size(600, 632), real: false);
      final h = tab(tester, 'history');
      final n = tester.getRect(find.bySemanticsIdentifier('snippet-new'));
      final p = tab(tester, 'privacy');
      final oneRow =
          (p.center.dy - h.center.dy).abs() < 1 &&
          (n.center.dy - h.center.dy).abs() < 12 &&
          p.right < n.left;
      expect(oneRow, isFalse);
    }, skip: skip != null);
  });
}
