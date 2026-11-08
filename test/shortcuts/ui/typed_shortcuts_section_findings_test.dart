// Repros for the tester's UI findings on M1.5 (see the hand-off). Each test
// states what the UI spec needs and FAILS today. Skipped in the normal run so
// the check stays green; run with
//   KUSUNGA_REPRO=1 flutter test test/shortcuts/ui/typed_shortcuts_section_findings_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/ui/typed_shortcuts_section.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';
import 'package:kusunga/theme/tokens.dart';

import '../../support/fakes.dart';
import '../fake_typed_shortcuts_port.dart';

void main() {
  late FakeTypedShortcutsPort port;
  late ShortcutService service;
  late Map<String, String> settings;
  var ignored = MemoryIgnoredAppStore();

  setUp(() {
    port = FakeTypedShortcutsPort();
    settings = {'typed_shortcuts_on': '0'};
    ignored = MemoryIgnoredAppStore();
  });

  Future<void> show(
    WidgetTester tester, {
    bool isMac = true,
    bool available = true,
    double width = 800,
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    service = ShortcutService(
      port: port,
      snippets: SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      ),
      ignoredApps: ignored,
      readSetting: (k) => settings[k],
      writeSetting: (k, v) {
        settings[k] = v;
        return true;
      },
      log: FakeLog(),
      isWindows: !isMac,
      available: available,
    );
    addTearDown(service.dispose);
    await tester.runAsync(service.start);
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TypedShortcutsSection(service: service, isMac: isMac),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(hook('typed-shortcuts-switch'));
    await tester.pumpAndSettle();
  }

  // widget tests take a bool; the reason is in the header above.
  final skip = !Platform.environment.containsKey('KUSUNGA_REPRO');

  // U1: the chip is not limited to the window width. A name cut to 30
  // characters is still wider than a 360 px window at 200% text (and at 1x
  // for wide letters), so the chip overflows and its Remove button is off
  // screen. The spec: "Chips wrap", "No sideways scrolling" at 320 px.
  testWidgets('U1 a long app name never overflows the chip row at 360 px and '
      '200% text', (tester) async {
    ignored.add(
      IgnoredApp(
        'com.example.long',
        'A banking app with a very long name indeed',
      ),
    );
    settings['typed_shortcuts_on'] = '1';
    await show(tester, width: 360, textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final r = tester.getRect(hook('ignored-app-remove-com.example.long'));
    expect(
      r.right,
      lessThanOrEqualTo(360),
      reason: 'Remove must stay on screen',
    );
  }, skip: skip);

  testWidgets('U1b the same at 360 px and normal text for a 30-character name '
      'of wide letters', (tester) async {
    ignored.add(IgnoredApp('com.example.wide', 'W' * 30));
    settings['typed_shortcuts_on'] = '1';
    await show(tester, width: 360);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: skip);

  // U2: removing a second app while the first toast is up hides that toast, so
  // the first Undo can no longer be pressed (the spec gives each removal an
  // Undo for 5 s).
  testWidgets(
    'U2 removing a second app keeps the first app\'s Undo reachable',
    (tester) async {
      await show(tester);
      await toggle(tester);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      await tester.tap(hook('ignored-app-remove-org.keepassxc.keepassxc'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Bitwarden removed'), findsOneWidget);
    },
    skip: skip,
  );
}
