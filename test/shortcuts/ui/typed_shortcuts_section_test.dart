// The "Typed shortcuts" section of the Snippets tab (M1.5 UI spec: states
// matrix, copy, accessibility notes, breakpoints).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';
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
  IgnoredAppStore ignored = MemoryIgnoredAppStore();

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
    tester.view.physicalSize = Size(width, 632);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
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
  SemanticsProperties props(WidgetTester tester, String id) =>
      tester.widget<Semantics>(hook(id)).properties;

  FocusNode switchNode(WidgetTester tester) => tester
      .widget<Switch>(find.byKey(const ValueKey('typed-shortcuts-switch')))
      .focusNode!;

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(hook('typed-shortcuts-switch'));
    await tester.pumpAndSettle();
  }

  group('switch', () {
    testWidgets('off by default: title, description, "Off", no status, no '
        'list', (tester) async {
      await show(tester);
      expect(find.text('Typed shortcuts'), findsOneWidget);
      expect(
        find.text(
          "Type a snippet's shortcut, like ;email, in any app to paste it.",
        ),
        findsOneWidget,
      );
      expect(find.text('Off'), findsOneWidget);
      final p = props(tester, 'typed-shortcuts-switch');
      expect(p.label, 'Typed shortcuts');
      expect(p.toggled, isFalse);
      expect(find.textContaining('Skipped in password fields'), findsNothing);
      expect(find.text('Add app…'), findsNothing);
      // The title is a heading.
      expect(
        tester
            .widget<Semantics>(
              find.ancestor(
                of: find.text('Typed shortcuts'),
                matching: find.byWidgetPredicate(
                  (w) => w is Semantics && (w.properties.header ?? false),
                ),
              ),
            )
            .properties
            .header,
        isTrue,
      );
    });

    testWidgets('on: "On", the status, the preset chips and the buttons', (
      tester,
    ) async {
      await show(tester);
      await toggle(tester);
      expect(settings['typed_shortcuts_on'], '1');
      expect(find.text('On'), findsOneWidget);
      expect(props(tester, 'typed-shortcuts-switch').toggled, isTrue);
      expect(
        find.text('On · Skipped in password fields and these apps:'),
        findsOneWidget,
      );
      for (final name in [
        '1Password',
        '1Password 7',
        'Bitwarden',
        'KeePassXC',
        'Passwords',
      ]) {
        expect(find.text(name), findsOneWidget);
        expect(
          props(
            tester,
            'ignored-app-remove-${presetIgnoredApps.firstWhere((a) => a.displayName == name).appId}',
          ).label,
          'Remove $name from ignored apps',
        );
      }
      expect(find.text('Add app…'), findsOneWidget);
      expect(
        props(tester, 'typed-shortcuts-add-app').label,
        'Add an app to ignore',
      );
      expect(find.text('Restore preset list'), findsNothing);
    });

    testWidgets('reduce motion: the switch jumps, it does not slide', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await show(tester);
      final before = tester.element(
        find.byKey(const ValueKey('typed-shortcuts-switch')),
      );
      await tester.tap(hook('typed-shortcuts-switch'));
      await tester.pump();
      // A new switch built at its end position: nothing to animate.
      final after = tester.element(
        find.byKey(const ValueKey('typed-shortcuts-switch')),
      );
      expect(identical(before, after), isFalse);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without reduce motion the switch slides', (tester) async {
      await show(tester);
      await tester.tap(hook('typed-shortcuts-switch'));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('Space toggles the focused switch', (tester) async {
      await show(tester);
      switchNode(tester).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(service.enabled, isTrue);
    });

    testWidgets('snippets unavailable: switch disabled with the reason', (
      tester,
    ) async {
      await show(tester, available: false);
      expect(
        find.text(
          "Typed shortcuts are off because snippets can't be opened right now.",
        ),
        findsOneWidget,
      );
      expect(props(tester, 'typed-shortcuts-switch').enabled, isFalse);
      await toggle(tester);
      expect(service.enabled, isFalse);
    });

    testWidgets('"Starting…" only when native takes over 300 ms', (
      tester,
    ) async {
      port.holdEnable = Completer<void>();
      await show(tester);
      await tester.tap(hook('typed-shortcuts-switch'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Starting…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Starting…'), findsOneWidget);
      port.holdEnable!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Starting…'), findsNothing);
    });

    testWidgets('C7: "Starting…" goes away when native answers the same '
        'status as before', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester);
      await tester.runAsync(() => service.setEnabled(true));
      await tester.pump();
      expect(service.status, TypedShortcutStatus.needsPermission);
      // Continue on the card: still not allowed, and native is slow.
      port.listenAnswer = true;
      port.holdEnable = Completer<void>();
      unawaited(service.requestPermission());
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Starting…'), findsOneWidget);
      port.holdEnable!.complete();
      await tester.pumpAndSettle();
      expect(service.busy, isFalse);
      expect(find.text('Starting…'), findsNothing);
      expect(
        find.textContaining('Needs Input Monitoring.'),
        findsOneWidget,
        reason: 'the unchanged status is shown again',
      );
    });
  });

  group('status line', () {
    Future<void> statusOf(WidgetTester tester, TypedShortcutStatus s) async {
      await show(tester);
      await toggle(tester);
      port.statusChanged(s);
      await tester.pump();
    }

    testWidgets('paused', (tester) async {
      await statusOf(tester, TypedShortcutStatus.paused);
      expect(
        find.text('Paused while another app protects your typing.'),
        findsOneWidget,
      );
    });

    testWidgets('stopped', (tester) async {
      await statusOf(tester, TypedShortcutStatus.stopped);
      expect(
        find.text('Typed shortcuts stopped. Turn them off and on again.'),
        findsOneWidget,
      );
    });

    testWidgets("couldn't start: the switch stays on to retry", (tester) async {
      port.onStatus = TypedShortcutStatus.failed;
      await show(tester, isMac: false);
      await toggle(tester);
      expect(find.text("Couldn't start typed shortcuts."), findsOneWidget);
      expect(props(tester, 'typed-shortcuts-switch').toggled, isTrue);
    });

    testWidgets('is a polite live region', (tester) async {
      await statusOf(tester, TypedShortcutStatus.on);
      expect(props(tester, 'typed-shortcuts-status').liveRegion, isTrue);
    });
  });

  group('Mac permission', () {
    testWidgets('turning on without permission opens the explanation card', (
      tester,
    ) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester);
      await toggle(tester);
      expect(find.text('Turn on typed shortcuts?'), findsOneWidget);
      expect(
        find.text(
          'To notice your shortcuts, Kusunga needs the Input Monitoring '
          'permission.',
        ),
        findsOneWidget,
      );
      for (final b in [
        'Kusunga keeps only the last few characters you type, for 5 seconds, '
            'in memory. It never saves or sends them.',
        'Password fields and the apps you list are always skipped.',
        'You can turn this off at any time.',
      ]) {
        expect(find.text(b), findsOneWidget);
      }
      expect(
        props(tester, 'typed-shortcuts-card').label,
        'Turn on typed shortcuts?',
      );
      // Focus starts on Continue.
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(
        Focus.of(tester.element(find.text('Continue'))).hasFocus,
        isTrue,
        reason: 'focus on Continue',
      );
      expect(continueButton, findsOneWidget);
      expect(port.calls, isNot(contains('requestListenAccess')));
    });

    testWidgets('Not now turns the switch back off and focuses it', (
      tester,
    ) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester);
      await toggle(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on typed shortcuts?'), findsNothing);
      expect(service.enabled, isFalse);
      expect(settings['typed_shortcuts_on'], '0');
      expect(switchNode(tester).hasFocus, isTrue);
    });

    testWidgets('Esc is Not now', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester);
      await toggle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(service.enabled, isFalse);
    });

    testWidgets('Continue asks macOS; granted: on', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester);
      await toggle(tester);
      port.listenAnswer = true;
      port.onStatus = TypedShortcutStatus.on;
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(port.calls, contains('requestListenAccess'));
      expect(find.text('Turn on typed shortcuts?'), findsNothing);
      expect(
        find.text('On · Skipped in password fields and these apps:'),
        findsOneWidget,
      );
    });

    testWidgets('Continue not granted: the status says so, with Open System '
        'Settings', (tester) async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      await show(tester);
      await toggle(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Needs Input Monitoring. Kusunga can't see your shortcuts until you "
          'allow it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Open System Settings'));
      await tester.pump();
      expect(port.calls.last, 'openInputMonitoringSettings');
    });

    testWidgets('Windows never shows the card', (tester) async {
      await show(tester, isMac: false);
      await toggle(tester);
      expect(find.text('Turn on typed shortcuts?'), findsNothing);
    });
  });

  group('ignored apps', () {
    testWidgets('Remove shows "<name> removed" with Undo for 5 s; Undo puts '
        'it back', (tester) async {
      await show(tester);
      await toggle(tester);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      expect(find.text('Bitwarden'), findsNothing);
      expect(find.text('Bitwarden removed'), findsOneWidget);
      expect(find.text('Restore preset list'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500)); // slides in
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Bitwarden'), findsOneWidget);
      expect(find.text('Restore preset list'), findsNothing);
    });

    testWidgets('Restore preset list', (tester) async {
      await show(tester);
      await toggle(tester);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      await tester.tap(hook('typed-shortcuts-restore-presets'));
      await tester.pump();
      expect(find.text('Preset list restored'), findsOneWidget);
      expect(find.text('Bitwarden'), findsOneWidget);
    });

    testWidgets('empty list', (tester) async {
      await show(tester);
      await toggle(tester);
      for (final a in List.of(service.ignoredApps)) {
        service.removeApp(a.appId);
      }
      await tester.pump();
      expect(
        find.text('No apps. Kusunga still skips password fields.'),
        findsOneWidget,
      );
    });

    testWidgets('a save that fails: the toast', (tester) async {
      ignored = _BrokenIgnored();
      await show(tester);
      await toggle(tester);
      await tester.tap(hook('ignored-app-remove-com.bitwarden.desktop'));
      await tester.pump();
      expect(find.text("Couldn't update the list. Try again."), findsOneWidget);
      expect(find.text('Bitwarden'), findsOneWidget);
    });

    testWidgets('a long name ends with an ellipsis; the full name is in the '
        'accessible name', (tester) async {
      final long = 'A banking app with a very long name indeed';
      ignored.add(IgnoredApp('com.example.long', long));
      await show(tester);
      await toggle(tester);
      expect(find.text(long), findsNothing);
      expect(find.textContaining('…'), findsWidgets);
      expect(
        props(tester, 'ignored-app-remove-com.example.long').label,
        'Remove $long from ignored apps',
      );
    });

    testWidgets('remove buttons are at least 24 px', (tester) async {
      await show(tester);
      await toggle(tester);
      final size = tester.getSize(
        hook('ignored-app-remove-com.bitwarden.desktop'),
      );
      expect(size.width, greaterThanOrEqualTo(24));
      expect(size.height, greaterThanOrEqualTo(24));
    });
  });

  group('Add app…', () {
    final png = Uint8List.fromList(_onePixelPng);

    testWidgets('lists running apps by name, marks added ones, searches, and '
        'Enter adds', (tester) async {
      port.apps = [
        RunningApp(appId: 'com.apple.Safari', name: 'Safari', icon: png),
        const RunningApp(appId: 'com.1password.1password', name: '1Password'),
        const RunningApp(appId: 'com.example.bank', name: 'My Bank'),
      ];
      await show(tester);
      await toggle(tester);
      await tester.tap(find.text('Add app…'));
      await tester.pumpAndSettle();
      expect(find.text('Choose an app'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(
        props(tester, 'add-app-row-com.1password.1password').enabled,
        isFalse,
      );
      await tester.enterText(find.byType(TextField), 'bank');
      await tester.pump();
      expect(find.text('Safari'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Choose an app'), findsNothing);
      expect(find.text('My Bank'), findsOneWidget);
      expect(port.ignoredSent.last, contains('com.example.bank'));
    });

    testWidgets('a click adds too', (tester) async {
      port.apps = const [
        RunningApp(appId: 'com.example.bank', name: 'My Bank'),
      ];
      await show(tester);
      await toggle(tester);
      await tester.tap(find.text('Add app…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Bank'));
      await tester.pumpAndSettle();
      expect(service.ignoredApps.last.appId, 'com.example.bank');
    });

    testWidgets('no other apps open', (tester) async {
      await show(tester);
      await toggle(tester);
      await tester.tap(find.text('Add app…'));
      await tester.pumpAndSettle();
      expect(
        find.text('No other apps are open. Open the app, then try again.'),
        findsOneWidget,
      );
    });

    testWidgets('the search field has its placeholder', (tester) async {
      await show(tester);
      await toggle(tester);
      await tester.tap(find.text('Add app…'));
      await tester.pumpAndSettle();
      expect(find.text('Search apps…'), findsOneWidget);
    });
  });

  group('breakpoints', () {
    testWidgets('320 px stand-in (360 px at 200% text): no overflow', (
      tester,
    ) async {
      await show(tester, width: 360, textScale: 2);
      await toggle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}

class _BrokenIgnored implements IgnoredAppStore {
  final _inner = MemoryIgnoredAppStore();
  @override
  List<IgnoredApp> list() => _inner.list();
  @override
  bool add(IgnoredApp app) => throw StateError('disk');
  @override
  IgnoredApp? remove(String appId) => throw StateError('disk');
  @override
  void restorePresets() => throw StateError('disk');
}

const _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
