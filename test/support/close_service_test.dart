// Windows CI green (group A): HistoryService.dispose() does not close the
// store, so a test that only disposes leaves kusunga.db open, and Windows
// refuses to delete an open file when the temp folder is removed (errno 32).
// The helper closes first, then disposes, and its tear-down runs before a
// folder deletion registered earlier.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';

import 'close_service.dart';
import 'fakes.dart';

class _CountingStore extends MemoryHistoryStore {
  int closes = 0;

  @override
  void close() => closes++;
}

HistoryService _service(_CountingStore store) =>
    HistoryService(store: store, source: FakeClipboardSource(), log: FakeLog())
      ..start();

void main() {
  test('dispose() alone leaves the store open (why the helper exists)', () {
    final store = _CountingStore();
    _service(store).dispose();
    expect(store.closes, 0);
  });

  test('closeAndDispose closes the store, then disposes', () async {
    final store = _CountingStore();
    final service = _service(store);
    await closeAndDispose(service);
    expect(store.closes, 1);
    // Disposed: a second dispose is a no-op and a listener cannot be added.
    expect(() => service.addListener(() {}), throwsFlutterError);
  });

  test('closeAndDispose after the service was already closed (for example '
      'by Delete everything) is safe', () async {
    final store = _CountingStore();
    final service = _service(store);
    await service.close();
    await closeAndDispose(service);
    expect(store.closes, 1);
  });

  group('addCloseTearDown', () {
    late _CountingStore store;
    // Registered before the test's own tear-down, so it runs after it, like
    // the folder deletion in the test files: by then the store is closed.
    tearDown(() => expect(store.closes, 1));

    test('runs before a tear-down registered earlier', () {
      store = _CountingStore();
      addCloseTearDown(_service(store));
      expect(store.closes, 0);
    });
  });
}
