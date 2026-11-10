// M1.6 fix round 2 (reviewer R4): a list that can't be read at start never
// reaches the clipboard watcher as an empty list.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';

import '../support/fakes.dart';

class _UnreadableList extends MemoryIgnoredAppStore {
  @override
  List<IgnoredApp> list() => throw StateError('database locked');
}

void main() {
  test(
    'HistoryService start sends the preset list, not an empty one',
    () async {
      final src = FakeClipboardSource();
      final log = FakeLog();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: src,
        log: log,
        ignoredAppStore: _UnreadableList(),
      );
      addTearDown(h.dispose);
      h.start();
      await pumpEventQueue();
      expect(src.sentIgnored, [for (final a in presetIgnoredApps) a.appId]);
      expect(log.codes, contains(LogCode.readFailed));
    },
  );
}
