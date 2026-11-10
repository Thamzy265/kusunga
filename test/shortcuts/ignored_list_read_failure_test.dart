// M1.6 fix round 2 (reviewer R4): when typed shortcuts can't read the
// ignore list at start, neither native side is sent an empty list; both get
// this system's preset list.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';
import 'package:kusunga/shortcuts/shortcut_service.dart';
import 'package:kusunga/snippets/memory_snippet_store.dart';
import 'package:kusunga/snippets/snippet_service.dart';

import '../support/fakes.dart';
import 'fake_typed_shortcuts_port.dart';

class _UnreadableList extends MemoryIgnoredAppStore {
  @override
  List<IgnoredApp> list() => throw StateError('database locked');
}

void main() {
  for (final isWindows in [false, true]) {
    test('start (${isWindows ? 'Windows' : 'Mac'}): both natives get this '
        "system's presets", () async {
      final port = FakeTypedShortcutsPort();
      final capture = <List<String>>[];
      final log = FakeLog();
      final s = ShortcutService(
        port: port,
        snippets: SnippetService(
          store: MemorySnippetStore(),
          log: FakeLog(),
          editable: true,
          writeClipboard: (_) async => true,
        ),
        ignoredApps: _UnreadableList(),
        readSetting: (_) => null,
        writeSetting: (_, _) => true,
        log: log,
        isWindows: isWindows,
        available: true,
        setCaptureIgnored: (ids) async {
          capture.add(ids);
          return true;
        },
      );
      addTearDown(s.dispose);
      await s.start();
      final presets = [
        for (final p in presetIgnoredApps)
          if (appIdIsForWindows(p.appId) == isWindows) p.appId,
      ];
      expect(presets, isNotEmpty);
      expect(port.ignoredSent, [presets]);
      expect(capture, [presets]);
      expect(s.ignoredApps.map((a) => a.appId), presets);
      expect(log.codes, contains(LogCode.readFailed));
    });
  }
}
