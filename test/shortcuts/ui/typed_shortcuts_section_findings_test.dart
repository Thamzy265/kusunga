// Regression tests for the tester's UI findings on M1.5: U1 (a long app name
// overflowed the chip row) and U2 (a second removal hid the first Undo).
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/ui/ignored_apps_editor.dart';
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
    bool editor = false,
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
            // M1.6: the list is edited in the Privacy tab's editor.
            child: editor
                ? IgnoredAppsEditor(service: service)
                : TypedShortcutsSection(service: service, isMac: isMac),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

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
    await show(tester, editor: true, width: 360, textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final r = tester.getRect(hook('ignored-app-remove-com.example.long'));
    expect(
      r.right,
      lessThanOrEqualTo(360),
      reason: 'Remove must stay on screen',
    );
  });

  testWidgets('U1b the same at 360 px and normal text for a 30-character name '
      'of wide letters', (tester) async {
    ignored.add(IgnoredApp('com.example.wide', 'W' * 30));
    settings['typed_shortcuts_on'] = '1';
    await show(tester, editor: true, width: 360);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // U2: removing a second app while the first toast is up hides that toast, so
  // the first Undo can no longer be pressed (the spec gives each removal an
  // Undo for 5 s).
  testWidgets(
    'U2 removing a second app keeps the first app\'s Undo reachable',
    (tester) async {
      await show(tester, editor: true);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      await tester.tap(hook('ignored-app-remove-org.keepassxc.keepassxc'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Bitwarden removed'), findsOneWidget);
    },
  );
}
