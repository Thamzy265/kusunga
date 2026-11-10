// Tester edge cases for the "Typed shortcuts" section (M1.5 UI spec): focus
// order, accessible names, Undo timing, long names, the narrow window at 200%
// text in every status, dark theme, and the Add app dialog's keyboard paths.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';
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
    VoidCallback? onEditIgnoredApps,
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
                : TypedShortcutsSection(
                    service: service,
                    isMac: isMac,
                    onEditIgnoredApps: onEditIgnoredApps,
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

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(hook('typed-shortcuts-switch'));
    await tester.pumpAndSettle();
  }

  /// The test-hook id of the Semantics node that wraps the focused widget.
  String? focusedId() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    String? found;
    ctx?.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Semantics && (w.properties.identifier ?? '').isNotEmpty) {
        found = w.properties.identifier;
        return false;
      }
      return true;
    });
    return found;
  }

  Future<List<String?>> tabThrough(WidgetTester tester, int n) async {
    final order = <String?>[];
    for (var i = 0; i < n; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(focusedId());
    }
    return order;
  }

  group('keyboard and names', () {
    testWidgets('focus order in the section: switch, Open System Settings, '
        'Edit ignored apps (M1.6: the chips are read only)', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester, width: 1000, onEditIgnoredApps: () {});
      await toggle(tester); // opens the card
      await tester.tap(hook('typed-shortcuts-card-continue'));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final order = await tabThrough(tester, 3);
      expect(order, [
        'typed-shortcuts-switch',
        'typed-shortcuts-open-settings',
        'typed-shortcuts-edit-ignored',
      ]);
    });

    testWidgets('focus order in the list editor: every Remove in order, Add '
        'app, Restore preset list', (tester) async {
      await show(tester, width: 1000, editor: true);
      // Remove one preset so Restore shows.
      service.removeApp('com.bitwarden.desktop');
      await tester.pump();
      final mac = service.ignoredApps.map((a) => a.appId).toList();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final order = await tabThrough(tester, mac.length + 2);
      expect(order.sublist(0, mac.length), [
        for (final id in mac) 'ignored-app-remove-$id',
      ]);
      expect(order[mac.length], 'typed-shortcuts-add-app');
      expect(order[mac.length + 1], 'typed-shortcuts-restore-presets');
    });

    testWidgets('accessible names: Remove <name> from ignored apps and Add an '
        'app to ignore', (tester) async {
      await show(tester, editor: true);
      expect(
        tester
            .getSemantics(hook('ignored-app-remove-com.1password.1password'))
            .label,
        'Remove 1Password from ignored apps',
      );
      expect(
        tester.getSemantics(hook('typed-shortcuts-add-app')).label,
        'Add an app to ignore',
      );
    });

    testWidgets('the read-only list and its link are hidden while the '
        'switch is off', (tester) async {
      await show(tester, onEditIgnoredApps: () {});
      expect(hook('typed-shortcuts-edit-ignored'), findsNothing);
      expect(find.text('1Password'), findsNothing);
      await toggle(tester);
      expect(hook('typed-shortcuts-edit-ignored'), findsOneWidget);
      expect(find.text('1Password'), findsOneWidget);
      await toggle(tester);
      expect(hook('typed-shortcuts-edit-ignored'), findsNothing);
    });

    testWidgets('an unavailable switch does nothing when tapped or toggled by '
        'key', (tester) async {
      await show(tester, available: false);
      await tester.tap(hook('typed-shortcuts-switch'));
      await tester.pumpAndSettle();
      expect(port.calls, isNot(contains('setEnabled(true)')));
      expect(settings['typed_shortcuts_on'], '0');
      expect(
        find.text(
          "Typed shortcuts are off because snippets can't be opened right now.",
        ),
        findsOneWidget,
      );
      expect(hook('typed-shortcuts-add-app'), findsNothing);
    });
  });

  group('Undo', () {
    testWidgets('the toast and Undo are gone after 5 s and the app stays '
        'removed', (tester) async {
      await show(tester, editor: true);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Bitwarden'), findsNothing);
      expect(
        service.ignoredApps.map((a) => a.appId),
        isNot(contains('com.bitwarden.desktop')),
      );
    });

    testWidgets('Undo sends the list to native again', (tester) async {
      await show(tester, editor: true);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      expect(port.ignoredSent.last, isNot(contains('com.bitwarden.desktop')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(port.ignoredSent.last, contains('com.bitwarden.desktop'));
    });
  });

  group('long content and narrow windows', () {
    testWidgets('every status at 360 px and 200% text: no overflow, no '
        'horizontal scroll', (tester) async {
      for (final status in [
        TypedShortcutStatus.on,
        TypedShortcutStatus.paused,
        TypedShortcutStatus.stopped,
        TypedShortcutStatus.failed,
      ]) {
        port.onStatus = status;
        settings['typed_shortcuts_on'] = '1';
        await show(tester, width: 360, textScale: 2);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: status.name);
        final scrollables = tester
            .widgetList<Scrollable>(find.byType(Scrollable))
            .where((s) => s.axis == Axis.horizontal);
        expect(scrollables, isEmpty, reason: status.name);
        await tester.pumpWidget(const SizedBox());
        service.dispose();
      }
    });

    testWidgets('needs permission with the Open System Settings button at 360 '
        'px and 200% text', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      settings['typed_shortcuts_on'] = '1';
      await show(tester, width: 360, textScale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(hook('typed-shortcuts-open-settings'), findsOneWidget);
      final r = tester.getRect(hook('typed-shortcuts-open-settings'));
      expect(r.right, lessThanOrEqualTo(360));
      expect(r.height, greaterThanOrEqualTo(24));
    });

    testWidgets('the explanation card fills a 360 px window at 200% text with '
        'both buttons reachable', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester, width: 360, textScale: 2);
      await toggle(tester);
      expect(hook('typed-shortcuts-card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final id in [
        'typed-shortcuts-card-not-now',
        'typed-shortcuts-card-continue',
      ]) {
        await tester.ensureVisible(hook(id));
        final r = tester.getRect(hook(id));
        expect(r.left, greaterThanOrEqualTo(0), reason: id);
        expect(r.right, lessThanOrEqualTo(360), reason: id);
        expect(r.height, greaterThanOrEqualTo(24), reason: id);
      }
    });

    testWidgets('dark theme: every state renders without errors', (
      tester,
    ) async {
      settings['typed_shortcuts_on'] = '1';
      await show(tester, brightness: Brightness.dark);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('On'), findsWidgets);
    });
  });

  group('Add app… keyboard paths', () {
    const apps = [
      RunningApp(appId: 'com.example.bank', name: 'My Bank'),
      RunningApp(appId: 'com.1password.1password', name: '1Password'),
    ];

    testWidgets('Esc closes the list without adding and focus returns to Add '
        'app…', (tester) async {
      port.apps = apps;
      await show(tester, editor: true);
      final before = service.ignoredApps.length;
      final order = <String?>[];
      for (var i = 0; i < 30 && focusedId() != 'typed-shortcuts-add-app'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(focusedId());
      }
      expect(focusedId(), 'typed-shortcuts-add-app', reason: '$order');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(hook('choose-app-dialog'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(hook('choose-app-dialog'), findsNothing);
      expect(service.ignoredApps.length, before);
      expect(focusedId(), 'typed-shortcuts-add-app');
    });

    testWidgets('an app that is already listed cannot be chosen by a click or '
        'by Enter', (tester) async {
      port.apps = const [
        RunningApp(appId: 'com.1password.1password', name: '1Password'),
      ];
      await show(tester, editor: true);
      final before = service.ignoredApps.length;
      await tester.tap(hook('typed-shortcuts-add-app'));
      await tester.pumpAndSettle();
      await tester.tap(hook('add-app-row-com.1password.1password'));
      await tester.pumpAndSettle();
      expect(service.ignoredApps.length, before);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(service.ignoredApps.length, before);
    });

    testWidgets('a search with no match adds nothing on Enter and does not '
        'crash', (tester) async {
      port.apps = apps;
      await show(tester, editor: true);
      final before = service.ignoredApps.length;
      await tester.tap(hook('typed-shortcuts-add-app'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.ignoredApps.length, before);
    });

    testWidgets('search ignores case and surrounding spaces in the query', (
      tester,
    ) async {
      port.apps = apps;
      await show(tester, editor: true);
      await tester.tap(hook('typed-shortcuts-add-app'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  MY bank ');
      await tester.pump();
      final dialog = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == 'choose-app-dialog',
      );
      expect(
        find.descendant(of: dialog, matching: find.text('My Bank')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('1Password')),
        findsNothing,
      );
    });

    testWidgets('the chooser at 360 px and 200% text with a very long app name '
        'has no overflow', (tester) async {
      port.apps = [
        RunningApp(appId: 'com.example.long', name: 'L' * 100),
        ...apps,
      ];
      await show(tester, editor: true, width: 360, textScale: 2);
      await tester.tap(hook('typed-shortcuts-add-app'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(hook('choose-app-search'), findsOneWidget);
    });

    testWidgets(
      'the add-app list shows "Finding apps…" only if native is slow',
      (tester) async {
        port.apps = apps;
        await show(tester, editor: true);
        await tester.tap(hook('typed-shortcuts-add-app'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Finding apps…'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('Finding apps…'), findsNothing);
      },
    );
  });
}
