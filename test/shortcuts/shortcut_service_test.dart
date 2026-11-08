// ShortcutService: the switch (off by default, D3 A), the table it keeps in
// step with the snippets, the ignore list, permission and status, and what
// happens on a match.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet.dart';
import 'package:kusunga/snippets/snippet_service.dart';

import '../support/fakes.dart';
import 'fake_typed_shortcuts_port.dart';

void main() {
  late FakeTypedShortcutsPort port;
  late SnippetService snippets;
  late MemoryIgnoredAppStore ignored;
  late Map<String, String> settings;
  late FakeLog log;
  late int copiedToasts;
  var saveOk = true;

  setUp(() {
    port = FakeTypedShortcutsPort();
    snippets = SnippetService(
      store: MemorySnippetStore(),
      log: FakeLog(),
      editable: true,
      writeClipboard: (_) async => true,
    );
    ignored = MemoryIgnoredAppStore();
    settings = {'typed_shortcuts_on': '0'};
    log = FakeLog();
    copiedToasts = 0;
    saveOk = true;
  });

  ShortcutService make({bool isWindows = false, bool available = true}) {
    final s = ShortcutService(
      port: port,
      snippets: snippets,
      ignoredApps: ignored,
      readSetting: (k) => settings[k],
      writeSetting: (k, v) {
        if (!saveOk) return false;
        settings[k] = v;
        return true;
      },
      log: log,
      isWindows: isWindows,
      available: available,
      onCopied: () => copiedToasts++,
    );
    addTearDown(s.dispose);
    return s;
  }

  int addSnippet(String name, String content, [String? shortcut]) => snippets
      .save(
        name: name,
        content: content,
        type: SnippetType.other,
        shortcut: shortcut,
      )
      .id!;

  group('start', () {
    test(
      'off by default: the table and the list are sent, nothing watches',
      () async {
        addSnippet('Work email', 'will@example.com', ';email');
        final s = make();
        await s.start();
        expect(s.enabled, isFalse);
        expect(s.status, TypedShortcutStatus.off);
        expect(port.calls, isNot(contains('setEnabled(true)')));
        expect(port.tables.last.map((e) => e.shortcut), [';email']);
        expect(log.codes, contains(LogCode.shortcutTableSize));
        expect(log.details[log.codes.indexOf(LogCode.shortcutTableSize)], 1);
      },
    );

    test('on from the setting: watching starts', () async {
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      expect(s.enabled, isTrue);
      expect(s.status, TypedShortcutStatus.on);
      expect(port.calls.last, 'setEnabled(true)');
    });

    test(
      'snippets that can not be opened: unavailable, never watched',
      () async {
        settings['typed_shortcuts_on'] = '1';
        final s = make(available: false);
        await s.start();
        expect(s.available, isFalse);
        expect(port.calls, isNot(contains('setEnabled(true)')));
        expect(await s.setEnabled(true), isNull);
        expect(port.calls, isNot(contains('setEnabled(true)')));
      },
    );

    test('only this system\'s ignored apps are shown and sent', () async {
      final mac = make();
      await mac.start();
      expect(mac.ignoredApps.map((a) => a.appId), [
        'com.1password.1password',
        'com.agilebits.onepassword7',
        'com.bitwarden.desktop',
        'org.keepassxc.keepassxc',
        'com.apple.Passwords',
      ]);
      expect(port.ignoredSent.last, mac.ignoredApps.map((a) => a.appId));
      port.ignoredSent.clear();
      final win = make(isWindows: true);
      await win.start();
      expect(win.ignoredApps.map((a) => a.appId), [
        '1password.exe',
        'bitwarden.exe',
        'keepassxc.exe',
        'keepass.exe',
      ]);
      expect(port.ignoredSent.last, win.ignoredApps.map((a) => a.appId));
    });
  });

  group('the switch', () {
    test('on and off are saved and sent', () async {
      final s = make();
      await s.start();
      expect(await s.setEnabled(true), TypedShortcutStatus.on);
      expect(settings['typed_shortcuts_on'], '1');
      expect(await s.setEnabled(false), TypedShortcutStatus.off);
      expect(settings['typed_shortcuts_on'], '0');
      expect(port.calls.last, 'setEnabled(false)');
    });

    test('Mac without permission: needsPermission, never a prompt', () async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      final s = make();
      await s.start();
      expect(await s.setEnabled(true), TypedShortcutStatus.needsPermission);
      expect(s.enabled, isTrue, reason: 'the switch stays on');
      expect(port.calls, isNot(contains('requestListenAccess')));
      expect(log.codes, contains(LogCode.shortcutPermissionMissing));
    });

    test('Continue asks macOS once; granted means on', () async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      final s = make();
      await s.start();
      await s.setEnabled(true);
      port.listenAnswer = true;
      port.onStatus = TypedShortcutStatus.on;
      expect(await s.requestPermission(), isTrue);
      expect(s.status, TypedShortcutStatus.on);
      expect(port.calls.where((c) => c == 'requestListenAccess').length, 1);
    });

    test('Continue not granted: still needsPermission', () async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      final s = make();
      await s.start();
      await s.setEnabled(true);
      expect(await s.requestPermission(), isFalse);
      expect(s.status, TypedShortcutStatus.needsPermission);
    });

    test('back in Kusunga: the permission is checked again', () async {
      port.onStatus = TypedShortcutStatus.needsPermission;
      final s = make();
      await s.start();
      await s.setEnabled(true);
      port.onStatus = TypedShortcutStatus.on;
      await s.recheck();
      expect(s.status, TypedShortcutStatus.on);
    });

    test('recheck does nothing while off', () async {
      final s = make();
      await s.start();
      port.calls.clear();
      await s.recheck();
      expect(port.calls, isEmpty);
    });

    test('Open System Settings', () async {
      final s = make();
      await s.start();
      await s.openSettings();
      expect(port.calls.last, 'openInputMonitoringSettings');
    });

    test('status changes from native are shown and logged once', () async {
      final s = make();
      await s.start();
      await s.setEnabled(true);
      port.statusChanged(TypedShortcutStatus.paused);
      expect(s.status, TypedShortcutStatus.paused);
      port.statusChanged(TypedShortcutStatus.stopped);
      port.statusChanged(TypedShortcutStatus.stopped);
      expect(log.codes.where((c) => c == LogCode.shortcutTapFailed).length, 1);
    });

    test(
      'Windows: a hook that can not start logs shortcutHookFailed',
      () async {
        port.onStatus = TypedShortcutStatus.failed;
        final s = make(isWindows: true);
        await s.start();
        await s.setEnabled(true);
        expect(log.codes, contains(LogCode.shortcutHookFailed));
      },
    );

    test('a status change while off is ignored', () async {
      final s = make();
      await s.start();
      port.statusChanged(TypedShortcutStatus.on);
      expect(s.status, TypedShortcutStatus.off);
    });
  });

  group('the table follows the snippets', () {
    test('a new, changed or removed shortcut is sent again; other edits '
        'are not', () async {
      final s = make();
      await s.start();
      final sent = port.tables.length;
      final id = addSnippet('Work email', 'x', ';email');
      expect(port.tables.length, sent + 1);
      expect(port.tables.last, [(id: id, shortcut: ';email')]);
      addSnippet('No code', 'y');
      expect(port.tables.length, sent + 1, reason: 'same table');
      snippets.save(
        id: id,
        name: 'Work email',
        content: 'x',
        type: SnippetType.other,
        shortcut: ';work',
      );
      expect(port.tables.last, [(id: id, shortcut: ';work')]);
      snippets.delete(id);
      expect(port.tables.last, isEmpty);
    });
  });

  group('a match', () {
    test(
      'reads the snippet and asks native to replace; logs shortcutFired',
      () async {
        final id = addSnippet('Work email', 'will@example.com', ';email');
        settings['typed_shortcuts_on'] = '1';
        final s = make();
        await s.start();
        port.match(id, 6);
        await pumpEventQueue();
        expect(port.replaced, [(6, 'will@example.com')]);
        expect(log.codes, contains(LogCode.shortcutFired));
      },
    );

    test('cancelled is logged; copied shows the M1.3 toast', () async {
      final id = addSnippet('Work email', 'will@example.com', ';email');
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      port.replaceAnswer = ReplaceOutcome.cancelled;
      port.match(id, 6);
      await pumpEventQueue();
      expect(log.codes, contains(LogCode.shortcutCancelled));
      port.replaceAnswer = ReplaceOutcome.copied;
      port.match(id, 6);
      await pumpEventQueue();
      expect(copiedToasts, 1);
      expect(log.codes, contains(LogCode.pastePermissionMissing));
    });

    test('ignored while off, unknown snippet, or a replace running', () async {
      final id = addSnippet('Work email', 'will@example.com', ';email');
      final s = make();
      await s.start();
      port.match(id, 6);
      await pumpEventQueue();
      expect(port.replaced, isEmpty, reason: 'off');
      await s.setEnabled(true);
      port.match(999, 6);
      await pumpEventQueue();
      expect(port.replaced, isEmpty, reason: 'no such snippet');
      port.match(id, 6);
      port.match(id, 6);
      await pumpEventQueue();
      expect(port.replaced.length, 1, reason: 'one at a time');
    });

    test('no log line holds the shortcut, the text or an app name', () async {
      final id = addSnippet('Work email', 'will@example.com', ';email');
      settings['typed_shortcuts_on'] = '1';
      final s = make();
      await s.start();
      port.match(id, 6);
      await pumpEventQueue();
      expect(log.details.whereType<int>().every((d) => d < 100000), isTrue);
    });
  });

  group('ignored apps', () {
    test('remove, Undo, add, and restore the preset list', () async {
      final s = make();
      await s.start();
      expect(s.canRestorePresets, isFalse);
      final removed = s.removeApp('com.1password.1password')!;
      expect(s.ignoredApps.map((a) => a.appId), isNot(contains(removed.appId)));
      expect(port.ignoredSent.last, isNot(contains(removed.appId)));
      expect(s.canRestorePresets, isTrue);
      expect(s.undoRemove(removed), isTrue);
      expect(
        s.ignoredApps.map((a) => a.appId),
        contains('com.1password.1password'),
      );
      expect(
        s.addApp(const RunningApp(appId: 'com.example.bank', name: 'My Bank')),
        isTrue,
      );
      expect(port.ignoredSent.last, contains('com.example.bank'));
      s.removeApp('com.bitwarden.desktop');
      expect(s.restorePresets(), isTrue);
      expect(s.ignoredApps.length, 6);
      expect(s.canRestorePresets, isFalse);
    });

    test('a store that fails: false, the list stays', () async {
      final s = ShortcutService(
        port: port,
        snippets: snippets,
        ignoredApps: _BrokenIgnored(),
        readSetting: (k) => settings[k],
        writeSetting: (k, v) => true,
        log: log,
        isWindows: false,
        available: true,
      );
      addTearDown(s.dispose);
      await s.start();
      expect(s.removeApp('com.1password.1password'), isNull);
      expect(s.ignoredApps.length, 5);
      expect(s.restorePresets(), isFalse);
      expect(s.addApp(const RunningApp(appId: 'a.b', name: 'AB')), isFalse);
      expect(s.lastIgnoredFailed, isTrue);
    });

    test('running apps: this system only, Kusunga itself left out, sorted '
        'by name, and marked when already added', () async {
      port.apps = const [
        RunningApp(appId: 'com.wnasoni.kusunga', name: 'Kusunga'),
        RunningApp(appId: 'com.example.zed', name: 'Zed'),
        RunningApp(appId: 'com.1password.1password', name: '1Password'),
        RunningApp(appId: 'com.apple.Safari', name: 'Safari'),
      ];
      final s = make();
      await s.start();
      final apps = await s.runningApps();
      expect(apps.map((a) => a.app.name), ['1Password', 'Safari', 'Zed']);
      expect(apps.map((a) => a.added), [true, false, false]);
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
