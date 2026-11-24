// M1.7 tester: the Settings tab states matrix and accessibility notes
// (docs/ui/settings-and-expiry.md): dialog copy for every option, keyboard
// only, focus order with the approval button, narrow and large-text layouts
// with every note, targets, headings and a re-read of the OS each time the
// tab opens. Fakes only.
import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const day = Duration.millisecondsPerDay;

void main() {
  late FakeClipboardSource source;
  late FlakyStore store;
  late HistoryService service;
  late FakeLoginItemPort port;
  late LoginItemService loginItem;
  late FakeLog log;
  late int now;

  setUp(() {
    source = FakeClipboardSource();
    store = FlakyStore(MemoryHistoryStore());
    port = FakeLoginItemPort();
    log = FakeLog();
    now = 1000 * day;
  });

  void seed(Map<String, int> ageInDays) {
    final byAge = ageInDays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final MapEntry(key: text, value: age) in byAge) {
      store.inner.insertOrBump(text, ClipKind.text, now - age * day);
    }
  }

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(800, 632),
    double textScale = 1,
  }) async {
    service = HistoryService(
      store: store,
      source: source,
      log: log,
      clock: () => now,
    )..start();
    addTearDown(service.dispose);
    loginItem = LoginItemService(port: port, log: log);
    addTearDown(loginItem.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: KusungaTokens.themeData(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: HistoryHost(
          history: Future.value(service),
          initial: service,
          loginItem: loginItem,
        ),
      ),
    );
    await tester.pump();
  }

  Finder hook(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(hook('main-tab-settings'));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('auto-delete-menu')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-delete-menu')));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String option) async {
    await openMenu(tester);
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  bool hasFocus(WidgetTester tester, Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused is! Element || finder.evaluate().isEmpty) return false;
    final target = tester.element(finder);
    if (focused == target) return true;
    var found = false;
    focused.visitAncestorElements((a) => !(found = a == target));
    if (found) return true;
    var depth = 0;
    target.visitAncestorElements((a) {
      if (a == focused) found = true;
      return !found && ++depth < 6;
    });
    return found;
  }

  group('the confirm dialog copy, every option', () {
    const options = {1: 'After 1 day', 7: 'After 7 days', 30: 'After 30 days'};
    const words = {1: '1 day', 7: '7 days', 30: '30 days'};
    // From Never, every shorter time asks, and says the time it names.
    for (final days in [1, 7, 30]) {
      testWidgets('from Never to ${words[days]}: names the time, counts only '
          'items older than it', (tester) async {
        seed({
          'a': days + 1,
          'b': days + 5,
          'keep1': days - 1 < 0 ? 0 : days - 1,
          'keep2': 0,
        });
        await show(tester);
        await openSettings(tester);
        await pick(tester, options[days]!);
        expect(
          find.text(
            'Delete items after ${words[days]}? 2 older items will be '
            "deleted. Snippets aren't affected.",
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pump();
        expect(find.text('2 items deleted'), findsOneWidget);
        expect(store.inner.count, 2);
      });
    }

    testWidgets('an item exactly as old as the time is not counted or '
        'deleted', (tester) async {
      seed({'edge': 7, 'older': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      expect(find.textContaining('1 older item will'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      expect(store.inner.list().map((i) => i.preview), ['edge']);
    });

    testWidgets('Escape is Cancel: nothing is deleted, the old value stays, '
        'no toast', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.expiry.days, 30);
      expect(store.inner.count, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('After 30 days'), findsOneWidget);
    });

    testWidgets('Enter with the first focus (Cancel) deletes nothing', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.expiry.days, 30);
      expect(store.inner.count, 1);
    });

    testWidgets('Tab then Enter on Delete deletes (keyboard only)', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        hasFocus(tester, find.widgetWithText(FilledButton, 'Delete')),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.expiry.days, 7);
      expect(store.inner.count, 0);
    });

    testWidgets('the focus goes back to the menu after the dialog closes', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(hasFocus(tester, hook('settings-auto-delete')), isTrue);
    });
  });

  group('auto-delete menu', () {
    testWidgets('choosing the value it already has does nothing: no save, no '
        'dialog, no log', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '7');
      seed({'a': 30});
      await show(tester);
      await openSettings(tester);
      final before = List.of(log.codes);
      await pick(tester, 'After 7 days');
      expect(find.byType(AlertDialog), findsNothing);
      expect(log.codes, before);
    });

    testWidgets('keyboard only: Tab to the menu, Enter opens, Down + Enter '
        'chooses', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '7');
      await show(tester);
      await openSettings(tester);
      for (
        var i = 0;
        i < 8 && !hasFocus(tester, hook('settings-auto-delete'));
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(hasFocus(tester, hook('settings-auto-delete')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.expiry.days, 30);
      expect(find.text('After 30 days'), findsOneWidget);
    });

    testWidgets('a save error is announced (live region) and goes away when '
        'a later save works', (tester) async {
      final handle = tester.ensureSemantics();
      store.inner.writeSetting(historyExpirySetting, '7');
      await show(tester);
      await openSettings(tester);
      store.failWrites = true;
      await pick(tester, 'After 30 days');
      final node = tester.getSemantics(find.text("Couldn't save. Try again."));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      store.failWrites = false;
      await pick(tester, 'Never');
      expect(find.text("Couldn't save. Try again."), findsNothing);
      handle.dispose();
    });

    testWidgets('the saved value is what History reads after a restart-like '
        'rebuild: Never then 1 day', (tester) async {
      seed({'a': 3});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 1 day');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      expect(store.inner.readSetting(historyExpirySetting), '1');
    });
  });

  group('launch at login', () {
    testWidgets('the OS is read again every time the Settings tab opens', (
      tester,
    ) async {
      await show(tester);
      await openSettings(tester);
      expect(port.statusCalls, 1);
      await tester.tap(hook('main-tab-history'));
      await tester.pump();
      expect(port.statusCalls, 1, reason: 'leaving does not read');
      port.next = const LoginItemAnswer(LoginItemState.on);
      await openSettings(tester);
      expect(port.statusCalls, 2);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('the switch never shows on when the OS then says off', (
      tester,
    ) async {
      port.next = const LoginItemAnswer(LoginItemState.on);
      await show(tester);
      await openSettings(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      port.next = const LoginItemAnswer(LoginItemState.off);
      await tester.tap(hook('main-tab-history'));
      await tester.pump();
      await openSettings(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('Tab order with the approval button: switch, Open Login '
        'Items, Keep, Auto-delete, link', (tester) async {
      port.next = const LoginItemAnswer(LoginItemState.needsApproval);
      await show(tester);
      await openSettings(tester);
      final order = <String>[];
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final (id, name) in [
          ('settings-launch-at-login', 'login'),
          ('settings-open-login-items', 'open'),
          ('settings-auto-delete', 'auto'),
          ('settings-privacy-link', 'link'),
        ]) {
          if (hasFocus(tester, hook(id)) && !order.contains(name)) {
            order.add(name);
          }
        }
        if (hasFocus(tester, find.byKey(const Key('limit-field'))) &&
            !order.contains('keep')) {
          order.add('keep');
        }
      }
      expect(order, ['login', 'open', 'keep', 'auto', 'link']);
    });

    testWidgets('the switch works from the keyboard (Space)', (tester) async {
      await show(tester);
      await openSettings(tester);
      port.next = const LoginItemAnswer(LoginItemState.on);
      for (
        var i = 0;
        i < 4 && !hasFocus(tester, hook('settings-launch-at-login'));
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(port.setCalls, [true]);
    });

    testWidgets('turning it off announces "Launch at login off"', (
      tester,
    ) async {
      port.next = const LoginItemAnswer(LoginItemState.on);
      await show(tester);
      await openSettings(tester);
      port.next = const LoginItemAnswer(LoginItemState.off);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.bySemanticsLabel('Launch at login off'), findsOneWidget);
      expect(log.codes, contains(LogCode.loginItemOff));
    });
  });

  group('accessibility', () {
    testWidgets('General and History are headings in the Settings panel', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await openSettings(tester);
      for (final h in ['General']) {
        final node = tester.getSemantics(find.text(h)).getSemanticsData();
        expect(node.flagsCollection.isHeader, isTrue, reason: h);
      }
      final history = find.descendant(
        of: find.byType(Scaffold),
        matching: find.text('History'),
      );
      final headers = [
        for (final e in history.evaluate())
          tester.getSemantics(find.byWidget(e.widget)).getSemanticsData(),
      ].where((n) => n.flagsCollection.isHeader);
      expect(headers, isNotEmpty);
      handle.dispose();
    });

    testWidgets('targets are at least 24 x 24 at every text size', (
      tester,
    ) async {
      port.next = const LoginItemAnswer(LoginItemState.needsApproval);
      for (final scale in [1.0, 2.0]) {
        await show(tester, textScale: scale);
        await openSettings(tester);
        for (final id in [
          'settings-launch-at-login',
          'settings-open-login-items',
          'settings-auto-delete',
          'settings-privacy-link',
        ]) {
          final size = tester.getSize(hook(id));
          expect(size.width, greaterThanOrEqualTo(24), reason: '$id@$scale');
          expect(size.height, greaterThanOrEqualTo(24), reason: '$id@$scale');
        }
      }
    });

    testWidgets('every note is read with its control: the failed note is the '
        "switch's hint, and the macOS 12 note too", (tester) async {
      final handle = tester.ensureSemantics();
      for (final (state, note) in [
        (LoginItemState.unsupported, 'Needs macOS 13 or later.'),
        (LoginItemState.turnedOffInTaskManager, 'Turned off in Task Manager.'),
        (
          LoginItemState.needsApproval,
          'Allow Kusunga in System Settings › General › Login Items.',
        ),
      ]) {
        port.next = LoginItemAnswer(state);
        await show(tester);
        await openSettings(tester);
        final node = tester
            .getSemantics(hook('settings-launch-at-login'))
            .getSemanticsData();
        expect(node.hint, note, reason: '$state');
        expect(node.flagsCollection.isToggled, isNot(Tristate.none));
      }
      handle.dispose();
    });
  });

  group('layout: no sideways scroll, nothing wider than the window', () {
    final states = [
      LoginItemState.off,
      LoginItemState.on,
      LoginItemState.needsApproval,
      LoginItemState.failed,
      LoginItemState.unsupported,
      LoginItemState.turnedOffInTaskManager,
    ];
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} px at ${(scale * 100).toInt()}% text, '
            'every login state, the save error showing', (tester) async {
          store.inner.writeSetting(historyExpirySetting, '7');
          for (final state in states) {
            port.next = LoginItemAnswer(state);
            await show(tester, size: Size(width, 640), textScale: scale);
            await openSettings(tester);
            store.failWrites = true;
            await pick(tester, 'After 30 days');
            store.failWrites = false;
            expect(tester.takeException(), isNull, reason: '$state');
            expect(find.text("Couldn't save. Try again."), findsOneWidget);
            for (final e in find.byType(Text).evaluate()) {
              final box = e.renderObject! as RenderBox;
              if (!box.attached || !box.hasSize) continue;
              final r = box.localToGlobal(Offset.zero) & box.size;
              expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$state');
              expect(
                r.right,
                lessThanOrEqualTo(width + 0.5),
                reason: '$state ${(e.widget as Text).data}',
              );
            }
            final horizontal = tester
                .widgetList<Scrollable>(find.byType(Scrollable))
                .where(
                  (s) =>
                      s.axis == Axis.horizontal &&
                      s.restorationId != 'editable', // a text field
                );
            expect(horizontal, isEmpty, reason: '$state');
            // Its content can still be reached by scrolling down.
            await tester.ensureVisible(
              find.text('Ignored apps and pause are in Privacy'),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
              find.text('Ignored apps and pause are in Privacy'),
              findsOneWidget,
            );
          }
        });
      }
    }
  });
}
