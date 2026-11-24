// M1.6 UI spec: the ignored-apps list is edited only in the Privacy tab
// (IgnoredAppsEditor, always shown). The Typed shortcuts section keeps a
// read-only chip list and an "Edit ignored apps" link.
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
  late ShortcutService service;
  late Map<String, String> settings;
  late MemoryIgnoredAppStore ignored;

  setUp(() {
    settings = {'typed_shortcuts_on': '0'};
    ignored = MemoryIgnoredAppStore();
  });

  Future<void> show(WidgetTester tester, Widget Function() child) async {
    service = ShortcutService(
      port: FakeTypedShortcutsPort(),
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
      isWindows: false,
      available: true,
    );
    addTearDown(service.dispose);
    await tester.runAsync(service.start);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child())),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  group('Typed shortcuts section', () {
    testWidgets('on: read-only chips and "Edit ignored apps"', (tester) async {
      settings['typed_shortcuts_on'] = '1';
      var edits = 0;
      await show(
        tester,
        () => TypedShortcutsSection(
          service: service,
          isMac: true,
          onEditIgnoredApps: () => edits++,
        ),
      );
      expect(find.text('Bitwarden'), findsOneWidget);
      expect(
        hook('typed-shortcuts-ignored-com.bitwarden.desktop'),
        findsOneWidget,
      );
      // No editing here.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.identifier ?? '').startsWith('ignored-app-remove-'),
        ),
        findsNothing,
      );
      expect(find.text('Add app…'), findsNothing);
      expect(find.text('Restore preset list'), findsNothing);
      expect(find.text('Edit ignored apps'), findsOneWidget);
      await tester.tap(hook('typed-shortcuts-edit-ignored'));
      expect(edits, 1);
    });

    testWidgets('off: no chips and no link (as the chips)', (tester) async {
      await show(
        tester,
        () => TypedShortcutsSection(
          service: service,
          isMac: true,
          onEditIgnoredApps: () {},
        ),
      );
      expect(find.text('Bitwarden'), findsNothing);
      expect(find.text('Edit ignored apps'), findsNothing);
    });

    testWidgets('the link is a text button with at least a 24 px target', (
      tester,
    ) async {
      settings['typed_shortcuts_on'] = '1';
      await show(
        tester,
        () => TypedShortcutsSection(
          service: service,
          isMac: true,
          onEditIgnoredApps: () {},
        ),
      );
      final size = tester.getSize(hook('typed-shortcuts-edit-ignored'));
      expect(size.height, greaterThanOrEqualTo(24));
      expect(
        find.ancestor(
          of: find.text('Edit ignored apps'),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
    });
  });

  group('IgnoredAppsEditor', () {
    testWidgets('always shown, also with typed shortcuts off', (tester) async {
      await show(tester, () => IgnoredAppsEditor(service: service));
      expect(service.enabled, isFalse);
      for (final p in presetIgnoredApps.where(
        (p) => !appIdIsForWindows(p.appId),
      )) {
        expect(hook('ignored-app-remove-${p.appId}'), findsOneWidget);
      }
      expect(find.text('Add app…'), findsOneWidget);
    });

    testWidgets('removing here reaches typed shortcuts and the watcher', (
      tester,
    ) async {
      await show(tester, () => IgnoredAppsEditor(service: service));
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      expect(
        service.ignoredApps.map((a) => a.appId),
        isNot(contains('com.bitwarden.desktop')),
      );
      expect(find.text('Bitwarden removed'), findsOneWidget);
    });

    testWidgets('empty: the M1.6 copy', (tester) async {
      await show(tester, () => IgnoredAppsEditor(service: service));
      for (final a in List.of(service.ignoredApps)) {
        service.removeApp(a.appId);
      }
      await tester.pump();
      expect(
        find.text(
          'No apps. Kusunga still skips anything an app marks as private.',
        ),
        findsOneWidget,
      );
    });
  });
}
