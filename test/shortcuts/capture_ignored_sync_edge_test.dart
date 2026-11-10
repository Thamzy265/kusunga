// M1.6 tester: the shared ignore list (decision D1 A) under failure and in
// the unavailable modes: one list, both natives, whatever goes wrong with one
// of them.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/shortcuts/typed_shortcuts_port.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';

import '../support/fakes.dart';
import 'fake_typed_shortcuts_port.dart';

void main() {
  late FakeTypedShortcutsPort port;
  late MemoryIgnoredAppStore ignored;

  setUp(() {
    port = FakeTypedShortcutsPort();
    ignored = MemoryIgnoredAppStore();
  });

  ShortcutService make({
    required Future<bool> Function(List<String>) capture,
    bool isWindows = false,
    bool available = true,
  }) {
    final s = ShortcutService(
      port: port,
      snippets: SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      ),
      ignoredApps: ignored,
      readSetting: (_) => null,
      writeSetting: (_, _) => true,
      log: FakeLog(),
      isWindows: isWindows,
      available: available,
      setCaptureIgnored: capture,
    );
    addTearDown(s.dispose);
    return s;
  }

  test('unavailable (memory-only or newer file): editing the list still '
      'reaches the watcher', () async {
    final sent = <List<String>>[];
    final s = make(
      available: false,
      capture: (ids) async {
        sent.add(ids);
        return true;
      },
    );
    await s.start();
    sent.clear();
    expect(s.removeApp('com.bitwarden.desktop'), isNotNull);
    expect(sent, hasLength(1));
    expect(sent.single, isNot(contains('com.bitwarden.desktop')));
  });

  test('a watcher call that throws does not stop typed shortcuts getting '
      'the list', () async {
    Future<bool> boom(List<String> ids) async {
      throw StateError('channel');
    }

    final s = make(capture: boom);
    await s.start();
    port.ignoredSent.clear();
    s.removeApp('com.bitwarden.desktop');
    await pumpEventQueue();
    expect(port.ignoredSent, hasLength(1));
  });

  test(
    'a watcher call that never answers does not block start or edits',
    () async {
      final never = Completer<bool>();
      final s = make(capture: (ids) => never.future);
      await s.start().timeout(const Duration(seconds: 2));
      port.ignoredSent.clear();
      s.removeApp('com.bitwarden.desktop');
      await pumpEventQueue();
      expect(port.ignoredSent, hasLength(1));
    },
  );

  test('Windows sends only exe names, Mac only bundle ids', () async {
    final win = <List<String>>[];
    final w = make(
      isWindows: true,
      capture: (ids) async {
        win.add(ids);
        return true;
      },
    );
    await w.start();
    expect(win.single, isNotEmpty);
    expect(win.single.every(appIdIsForWindows), isTrue);

    final mac = <List<String>>[];
    final m = make(
      capture: (ids) async {
        mac.add(ids);
        return true;
      },
    );
    await m.start();
    expect(mac.single, isNotEmpty);
    expect(mac.single.any(appIdIsForWindows), isFalse);
  });

  test(
    'both natives get the same ids in the same order after each edit',
    () async {
      final sent = <List<String>>[];
      final s = make(
        capture: (ids) async {
          sent.add(ids);
          return true;
        },
      );
      await s.start();
      port.ignoredSent.clear();
      sent.clear();
      s.addApp(const RunningApp(appId: 'com.example.one', name: 'One'));
      s.addApp(const RunningApp(appId: 'com.example.two', name: 'Two'));
      s.removeApp('com.example.one');
      await pumpEventQueue();
      expect(sent, port.ignoredSent);
      expect(sent.last, contains('com.example.two'));
      expect(sent.last, isNot(contains('com.example.one')));
    },
  );

  test('a very long app id and a duplicate add pass through safely', () async {
    final sent = <List<String>>[];
    final s = make(
      capture: (ids) async {
        sent.add(ids);
        return true;
      },
    );
    await s.start();
    sent.clear();
    final long = 'a' * 255;
    expect(s.addApp(RunningApp(appId: long, name: 'Long')), isTrue);
    expect(sent.last, contains(long));
    // A second add of the same id changes nothing (the store refuses it).
    s.addApp(RunningApp(appId: long, name: 'Long'));
    expect(sent.last.where((i) => i == long), hasLength(1));
    // Over the table's limit: refused, the list sent stays valid.
    final before = sent.length;
    s.addApp(RunningApp(appId: 'b' * 256, name: 'TooLong'));
    if (sent.length > before) {
      expect(sent.last.any((i) => i.length > 255), isFalse);
    }
  });
}
