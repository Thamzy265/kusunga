// Shared by the M1.9a round 5 tests (B2, B3, B4): Settings under the same
// traversal policy as the main window (`history_host.dart`), with a stand-in
// licence registry, and the finders and key helpers they use.
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/about/build_info.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/settings/ui/settings_screen.dart';
import 'package:kusunga/settings/ui/your_data_section.dart';
import 'package:kusunga/theme/tokens.dart';
import 'package:kusunga/ui/focus_order.dart';

import '../support/fakes.dart';

const _release = BuildInfo(version: '0.9.0', build: '1', development: false);

/// The About buttons in Tab order.
const aboutButtonIds = [
  'about-copy-version',
  'about-copy-link',
  'about-view-licences',
];

Future<void> showSettings(
  WidgetTester tester, {
  Size size = const Size(800, 632),
  double textScale = 1,
}) async {
  final service = HistoryService(
    store: MemoryHistoryStore(),
    source: FakeClipboardSource(),
    log: FakeLog(),
  )..start();
  addTearDown(service.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  LicenseRegistry.reset();
  LicenseRegistry.addLicense(
    () => Stream.value(LicenseEntryWithLineBreaks(['Kusunga'], 'text')),
  );
  addTearDown(LicenseRegistry.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: KusungaTokens.themeData(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: FocusTraversalGroup(
        policy: revealingReadingOrder(),
        child: SettingsScreen(
          service: service,
          onShowPrivacy: () {},
          buildInfo: _release,
          yourData: YourDataSetup(
            files: FakeFilePort(),
            log: FakeLog(),
            eraser: () => throw UnimplementedError(),
            quit: () async {},
          ),
        ),
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

/// The box Settings scrolls in.
Rect settingsView(WidgetTester tester) =>
    tester.getRect(find.byType(SingleChildScrollView).first);

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

Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pump();
}

/// Tab from the top (nothing scrolled by hand) until [f] has the focus.
Future<void> tabTo(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && !hasFocus(tester, f); i++) {
    await key(tester, LogicalKeyboardKey.tab);
  }
  expect(hasFocus(tester, f), isTrue, reason: 'could not Tab to $f');
}
