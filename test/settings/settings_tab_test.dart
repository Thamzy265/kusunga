// M1.7 UI spec (docs/ui/settings-and-expiry.md): the Settings tab after
// Privacy, its General and History sections, launch at login, the moved Keep
// field and picker shortcut, the Auto-delete menu with its confirm dialog,
// the link to Privacy, and the clean-up warning in History.
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/history/ui/limit_field.dart';
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
    Widget? pickerShortcut,
    bool withLoginItem = true,
    Set<HistoryNotice> notices = const {},
  }) async {
    service = HistoryService(
      store: store,
      source: source,
      log: log,
      notices: notices,
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
          loginItem: withLoginItem ? loginItem : null,
          pickerShortcutSlot: pickerShortcut,
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
    await tester.tap(find.byKey(const Key('auto-delete-menu')));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String option) async {
    await openMenu(tester);
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  /// The primary focus is on [finder]'s widget, inside it, or on the
  /// Focus right around it (a heading).
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

  group('the tab and its sections', () {
    testWidgets('Settings comes after Privacy, with General and History '
        'headings', (tester) async {
      await show(tester);
      final tabs = [
        'main-tab-history',
        'main-tab-snippets',
        'main-tab-privacy',
        'main-tab-settings',
      ];
      final xs = [for (final t in tabs) tester.getCenter(hook(t)).dx];
      expect(xs, [...xs]..sort());
      expect(find.text('Settings'), findsOneWidget);
      await openSettings(tester);
      for (final h in ['General', 'History']) {
        final semantics = tester.getSemantics(find.text(h).last);
        expect(semantics.flagsCollection.isHeader, isTrue, reason: h);
      }
    });

    testWidgets('Keep moved from History to Settings, unchanged', (
      tester,
    ) async {
      await show(tester);
      expect(find.byType(LimitField), findsNothing);
      // The History header keeps its title, count line and ⋯ menu.
      expect(find.byTooltip('More options'), findsOneWidget);
      expect(find.text('0 of 200 items'), findsOneWidget);
      await openSettings(tester);
      expect(find.byType(LimitField), findsOneWidget);
      expect(
        find.bySemanticsLabel('Number of history items to keep'),
        findsOneWidget,
      );
    });

    testWidgets('the picker shortcut slot shows in Settings, not History', (
      tester,
    ) async {
      await show(tester, pickerShortcut: const Text('shortcut row'));
      expect(find.text('shortcut row'), findsNothing);
      await openSettings(tester);
      expect(find.text('shortcut row'), findsOneWidget);
    });

    testWidgets('Keep in Settings still asks before lowering', (tester) async {
      for (var i = 0; i < 12; i++) {
        store.inner.insertOrBump('item $i', ClipKind.text, now + i);
      }
      await show(tester);
      await openSettings(tester);
      await tester.enterText(find.byKey(const Key('limit-field')), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Keep only the newest 10 items? 2 older items will be deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete 2 items'));
      await tester.pumpAndSettle();
      expect(store.inner.count, 10);
    });

    testWidgets('no sideways overflow at 360 px and 200% text', (tester) async {
      port.next = const LoginItemAnswer(LoginItemState.needsApproval);
      await show(tester, size: const Size(360, 640), textScale: 2);
      await openSettings(tester);
      await loginItem.refresh();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final menu = tester.getRect(find.byKey(const Key('auto-delete-menu')));
      expect(menu.right, lessThanOrEqualTo(360));
      expect(
        tester.getTopLeft(find.byKey(const Key('auto-delete-menu'))).dy,
        greaterThan(tester.getBottomLeft(find.text('Auto-delete')).dy - 1),
        reason: 'the menu goes under its label',
      );
      // The switch stays on the right of its label.
      expect(
        tester.getCenter(find.byType(Switch)).dx,
        greaterThan(tester.getCenter(find.text('Launch at login')).dx),
      );
    });
  });

  group('launch at login', () {
    testWidgets('off by default (AC2), read from the OS when the tab opens', (
      tester,
    ) async {
      await show(tester);
      expect(port.statusCalls, 0);
      await openSettings(tester);
      expect(port.statusCalls, 1);
      final s = tester.widget<Switch>(find.byType(Switch));
      expect(s.value, isFalse);
      expect(
        find.text('Start Kusunga in the menu bar when you log in.'),
        findsOneWidget,
      );
    });

    testWidgets('Windows help text', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await show(tester);
      await openSettings(tester);
      expect(
        find.text('Start Kusunga in the tray when you sign in.'),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('turning it on: the switch is on, logged and announced', (
      tester,
    ) async {
      await show(tester);
      await openSettings(tester);
      port.next = const LoginItemAnswer(LoginItemState.on);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(port.setCalls, [true]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(log.codes, contains(LogCode.loginItemOn));
      expect(find.bySemanticsLabel('Launch at login on'), findsOneWidget);
    });

    testWidgets('accessible name, on/off state and the note as its '
        'description', (tester) async {
      final handle = tester.ensureSemantics();
      port.next = const LoginItemAnswer(LoginItemState.failed);
      await show(tester);
      await openSettings(tester);
      // The switch's own node is merged up into its control's node.
      final node = tester
          .getSemantics(hook('settings-launch-at-login'))
          .getSemanticsData();
      expect(node.label, contains('Launch at login'));
      expect(node.hint, "Couldn't turn this on. Try again.");
      expect(node.flagsCollection.isToggled, isNot(Tristate.none));
      handle.dispose();
    });

    testWidgets('failed: back off, with the note', (tester) async {
      await show(tester);
      await openSettings(tester);
      port.next = const LoginItemAnswer(LoginItemState.failed, error: 1);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text("Couldn't turn this on. Try again."), findsOneWidget);
    });

    testWidgets('needs approval: on, the note and Open Login Items', (
      tester,
    ) async {
      await show(tester);
      await openSettings(tester);
      port.next = const LoginItemAnswer(LoginItemState.needsApproval);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(
        find.text('Allow Kusunga in System Settings › General › Login Items.'),
        findsOneWidget,
      );
      await tester.tap(hook('settings-open-login-items'));
      await tester.pump();
      expect(port.openCalls, 1);
    });

    testWidgets('macOS 12: off and disabled, with the note', (tester) async {
      port.next = const LoginItemAnswer(LoginItemState.unsupported);
      await show(tester);
      await openSettings(tester);
      final s = tester.widget<Switch>(find.byType(Switch));
      expect(s.value, isFalse);
      expect(s.onChanged, isNull);
      expect(find.text('Needs macOS 13 or later.'), findsOneWidget);
    });

    testWidgets('Windows: turned off in Task Manager', (tester) async {
      port.next = const LoginItemAnswer(LoginItemState.turnedOffInTaskManager);
      await show(tester);
      await openSettings(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Turned off in Task Manager.'), findsOneWidget);
    });

    testWidgets('while the OS call runs, the switch keeps its new position '
        'and taps are ignored', (tester) async {
      await show(tester);
      await openSettings(tester);
      final pending = port.hold();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(port.setCalls, [true]);
      pending.complete(const LoginItemAnswer(LoginItemState.on));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('without a login item (not desktop) there is no switch', (
      tester,
    ) async {
      await show(tester, withLoginItem: false);
      await openSettings(tester);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('General'), findsOneWidget);
    });
  });

  group('auto-delete', () {
    testWidgets('shows the saved value; label, options and help text', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      await show(tester);
      await openSettings(tester);
      expect(find.text('Auto-delete'), findsOneWidget);
      expect(find.text('After 30 days'), findsOneWidget);
      expect(
        find.text(
          "Items you haven't copied for this long are removed. Snippets are "
          'never removed.',
        ),
        findsOneWidget,
      );
      await openMenu(tester);
      for (final o in ['Never', 'After 1 day', 'After 7 days']) {
        expect(find.text(o), findsWidgets, reason: o);
      }
    });

    testWidgets('accessible name "Auto-delete history", value the option', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      await openSettings(tester);
      final node = tester
          .getSemantics(hook('settings-auto-delete'))
          .getSemanticsData();
      expect(node.label, contains('Auto-delete history'));
      expect('${node.label} ${node.value}', contains('Never'));
      handle.dispose();
    });

    testWidgets('a longer time or Never: saved, no dialog, no toast', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '7');
      seed({'a': 1});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 30 days');
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.expiry.days, 30);
      await pick(tester, 'Never');
      expect(service.expiry.days, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('shorter with nothing to delete: saved, no dialog', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 0});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 1 day');
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.expiry.days, 1);
      expect(store.inner.count, 1);
    });

    testWidgets('shorter with items: the dialog says how many; focus on '
        'Cancel; Cancel keeps the old setting', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 2, 'b': 3, 'keep': 0});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 1 day');
      expect(
        find.text(
          'Delete items after 1 day? 2 older items will be deleted. '
          "Snippets aren't affected.",
        ),
        findsOneWidget,
      );
      expect(
        hasFocus(tester, find.widgetWithText(TextButton, 'Cancel')),
        isTrue,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.expiry.days, 30);
      expect(store.inner.count, 3);
      expect(find.text('After 30 days'), findsOneWidget);
    });

    testWidgets('Delete removes them, keeps the new time and shows the toast', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8, 'b': 9, 'keep': 0});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      expect(
        find.textContaining('Delete items after 7 days? 2 older items'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      expect(service.expiry.days, 7);
      expect(store.inner.count, 1);
      expect(find.text('2 items deleted'), findsOneWidget);
      expect(find.text('After 7 days'), findsOneWidget);
    });

    testWidgets('one item: singular wording', (tester) async {
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 30 days');
      expect(find.byType(AlertDialog), findsNothing);
      await pick(tester, 'After 7 days');
      expect(
        find.text(
          'Delete items after 7 days? 1 older item will be deleted. '
          "Snippets aren't affected.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      expect(find.text('1 item deleted'), findsOneWidget);
    });

    testWidgets('count unreadable: the dialog says so, only Cancel works', (
      tester,
    ) async {
      store = FlakyStore(_CountFailsStore());
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      expect(find.text("Couldn't count the items. Try again."), findsOneWidget);
      final delete = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(delete.onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.expiry.days, 30);
    });

    testWidgets('delete failed: the dialog closes, a toast, old setting kept', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      store.failWrites = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text("Couldn't delete. Try again."), findsOneWidget);
      expect(service.expiry.days, 30);
      expect(find.text('After 30 days'), findsOneWidget);
      expect(store.inner.count, 1);
    });

    testWidgets('save failed (no dialog): the menu goes back, the error '
        'below', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '7');
      await show(tester);
      await openSettings(tester);
      store.failWrites = true;
      await pick(tester, 'After 30 days');
      expect(find.text('After 7 days'), findsOneWidget);
      expect(find.text("Couldn't save. Try again."), findsOneWidget);
      expect(log.codes, contains(LogCode.settingSaveFailed));
      store.failWrites = false;
      await pick(tester, 'After 30 days');
      expect(find.text("Couldn't save. Try again."), findsNothing);
    });

    testWidgets('the count follows live changes while the dialog is open', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8, 'b': 9});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      expect(find.textContaining('2 older items'), findsOneWidget);
      store.inner.deleteOlderThan(now - 9 * day + 1);
      source.copy('new copy');
      await tester.pump();
      expect(find.textContaining('1 older item will'), findsOneWidget);
    });

    testWidgets('the count reaching 0 while open closes it as Cancel', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      await show(tester);
      await openSettings(tester);
      await pick(tester, 'After 7 days');
      store.inner.deleteOlderThan(now);
      source.copy('new copy');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.expiry.days, 30);
    });
  });

  testWidgets('the Privacy link opens Privacy with the focus on the "Pause '
      'history" heading', (tester) async {
    await show(tester);
    await openSettings(tester);
    expect(find.text('Ignored apps and pause are in Privacy'), findsOneWidget);
    await tester.tap(hook('settings-privacy-link'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Pause history'), findsOneWidget);
    expect(hasFocus(tester, hook('privacy-pause-heading')), isTrue);
  });

  testWidgets('Tab order: launch at login, Keep, Auto-delete, the link', (
    tester,
  ) async {
    await show(tester);
    await openSettings(tester);
    final order = <String>[];
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (final (id, name) in [
        ('settings-launch-at-login', 'login'),
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
    expect(order, ['login', 'keep', 'auto', 'link']);
  });

  testWidgets('3 failed clean-ups: the warning banner in History', (
    tester,
  ) async {
    store.inner.writeSetting(historyExpirySetting, '1');
    store.failWrites = true;
    await show(tester);
    service.expiry.cleanUp();
    service.expiry.cleanUp();
    await tester.pump();
    expect(
      find.text("Couldn't remove old items. Kusunga will try again."),
      findsOneWidget,
    );
    store.failWrites = false;
    service.expiry.cleanUp();
    await tester.pump();
    expect(
      find.text("Couldn't remove old items. Kusunga will try again."),
      findsNothing,
    );
  });
}

class _CountFailsStore extends MemoryHistoryStore {
  @override
  int countOlderThan(int cutoffMs, {int? notBefore}) =>
      throw StateError('locked');
}
