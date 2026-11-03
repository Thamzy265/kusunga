import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_handle.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

void main() {
  HistoryService service() => HistoryService(
    store: MemoryHistoryStore(),
    source: FakeClipboardSource(),
    log: const NullErrorLog(),
  )..start();

  test('closing while the history is still opening returns at once', () async {
    final opening = Completer<HistoryService>();
    final handle = HistoryHandle(opening.future);
    await handle.close().timeout(const Duration(milliseconds: 200));
  });

  test('once open, closing closes the history', () async {
    final s = service();
    final handle = HistoryHandle(Future.value(s));
    await pumpEventQueue();
    var changed = 0;
    s.addListener(() => changed++);
    await handle.close();
    expect(changed, greaterThan(0), reason: 'close() notifies the listeners');
  });

  test('a history that failed to open does not break quitting', () async {
    final handle = HistoryHandle(Future.error(StateError('x')));
    await pumpEventQueue();
    await handle.close();
  });
}
