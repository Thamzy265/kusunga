// M1.6 decision D1 A: one ignore list for history and typed shortcuts. Every
// change to the list reaches both native sides: typed shortcuts
// (setIgnored) and the clipboard watcher (setCaptureIgnored).
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
  late List<List<String>> captureLists;

  setUp(() {
    port = FakeTypedShortcutsPort();
    ignored = MemoryIgnoredAppStore();
    captureLists = [];
  });

  ShortcutService make({bool isWindows = false}) {
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
      available: true,
      setCaptureIgnored: (ids) async {
        captureLists.add(ids);
        return true;
      },
    );
    addTearDown(s.dispose);
    return s;
  }

  List<String> macIds() => [
    for (final a in ignored.list())
      if (!appIdIsForWindows(a.appId)) a.appId,
  ];

  test('start sends the list to the watcher too', () async {
    await make().start();
    expect(captureLists, [macIds()]);
  });

  test('remove, undo, add and restore each reach the watcher', () async {
    final s = make();
    await s.start();
    captureLists.clear();
    final removed = s.removeApp('com.bitwarden.desktop')!;
    expect(captureLists.last, isNot(contains('com.bitwarden.desktop')));
    s.undoRemove(removed);
    expect(captureLists.last, contains('com.bitwarden.desktop'));
    s.addApp(const RunningApp(appId: 'com.example.vault', name: 'Vault'));
    expect(captureLists.last, contains('com.example.vault'));
    s.removeApp('com.1password.1password');
    s.restorePresets();
    expect(captureLists.last, contains('com.1password.1password'));
    expect(captureLists, hasLength(5));
    // Always the same list typed shortcuts get.
    expect(captureLists.last, macIds());
  });

  test('typed shortcuts off: the list still reaches the watcher', () async {
    final s = make();
    await s.start();
    expect(s.enabled, isFalse);
    captureLists.clear();
    s.removeApp('com.bitwarden.desktop');
    expect(captureLists, hasLength(1));
  });

  test('a failed change sends nothing new', () async {
    final s = ShortcutService(
      port: port,
      snippets: SnippetService(
        store: MemorySnippetStore(),
        log: FakeLog(),
        editable: true,
        writeClipboard: (_) async => true,
      ),
      ignoredApps: _FailingStore(),
      readSetting: (_) => null,
      writeSetting: (_, _) => true,
      log: FakeLog(),
      isWindows: false,
      available: true,
      setCaptureIgnored: (ids) async {
        captureLists.add(ids);
        return true;
      },
    );
    addTearDown(s.dispose);
    await s.start();
    captureLists.clear();
    expect(s.removeApp('x'), isNull);
    expect(captureLists, isEmpty);
  });
}

class _FailingStore extends MemoryIgnoredAppStore {
  @override
  IgnoredApp? remove(String appId) => throw StateError('disk');
}
