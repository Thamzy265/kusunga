// M1.8: after an import with "Also use the settings in this file", typed
// shortcuts follow the saved switch and the new ignore list at once.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';

import '../support/fakes.dart';
import 'fake_typed_shortcuts_port.dart';

void main() {
  late FakeTypedShortcutsPort port;
  late MemoryIgnoredAppStore ignored;
  late Map<String, String> settings;

  ShortcutService make({bool available = true}) {
    final s = ShortcutService(
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
      isWindows: false,
      available: available,
      onCopied: () {},
    );
    addTearDown(s.dispose);
    return s;
  }

  setUp(() {
    port = FakeTypedShortcutsPort();
    ignored = MemoryIgnoredAppStore();
    settings = {'typed_shortcuts_on': '0'};
  });

  test(
    'turns on when the imported setting is on, and sends the new list',
    () async {
      final s = make();
      await s.start();
      port.calls.clear();
      settings['typed_shortcuts_on'] = '1';
      ignored.add(const IgnoredApp('com.example.vault', 'Vault'));
      await s.reloadFromStore();
      expect(s.enabled, isTrue);
      expect(port.calls, containsAll(['setIgnored', 'setEnabled(true)']));
      expect(s.ignoredApps.map((a) => a.appId), contains('com.example.vault'));
    },
  );

  test('nothing to change: the switch is not called again', () async {
    final s = make();
    await s.start();
    port.calls.clear();
    await s.reloadFromStore();
    expect(port.calls, isNot(contains('setEnabled(false)')));
    expect(port.calls, isNot(contains('setEnabled(true)')));
  });

  test('not available (memory only): the switch stays off', () async {
    final s = make(available: false);
    await s.start();
    settings['typed_shortcuts_on'] = '1';
    await s.reloadFromStore();
    expect(s.enabled, isFalse);
  });
}
