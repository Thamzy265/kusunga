// M1.6 fix round 2 (reviewer R3): the ignore list sent to the clipboard
// watcher. A retry never sends an older list over a newer one.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';

import '../support/fakes.dart';

/// A watcher whose answers come when the test says so. Native code applies
/// each list when the call arrives, so the last list in [received] is what
/// the watcher holds.
class _Src extends FakeClipboardSource {
  final received = <List<String>>[];
  final _pending = <Completer<bool>>[];

  @override
  Future<bool> setCaptureIgnored(List<String> appIds) {
    received.add(List.of(appIds));
    final c = Completer<bool>();
    _pending.add(c);
    return c.future;
  }

  void answerNext(bool ok) => _pending.removeAt(0).complete(ok);
  int get waiting => _pending.length;
}

void main() {
  group('R3: a retry never overrides a newer list', () {
    const withVault = ['com.1password.1password', 'com.bitwarden.desktop'];
    const withoutVault = ['com.bitwarden.desktop'];

    test('remove 1Password fails, Undo works: the retry of the removal is '
        'dropped', () async {
      final src = _Src();
      final log = FakeLog();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: src,
        log: log,
      );
      addTearDown(h.dispose);
      final remove = h.setCaptureIgnored(withoutVault);
      final undo = h.setCaptureIgnored(withVault);
      src.answerNext(false); // the removal's first try fails
      src.answerNext(true); // Undo arrives
      await pumpEventQueue();
      while (src.waiting > 0) {
        src.answerNext(true);
        await pumpEventQueue();
      }
      await remove;
      expect(await undo, isTrue);
      expect(
        src.received.last,
        withVault,
        reason: '1Password must stay ignored natively after Undo',
      );
      expect(log.codes, isEmpty);
    });

    test(
      'a retry not superseded uses the latest list, which is its own',
      () async {
        final src = _Src();
        final h = HistoryService(
          store: MemoryHistoryStore(),
          source: src,
          log: FakeLog(),
        );
        addTearDown(h.dispose);
        final one = h.setCaptureIgnored(withoutVault);
        src.answerNext(false);
        await pumpEventQueue();
        src.answerNext(true);
        expect(await one, isTrue);
        expect(src.received, [withoutVault, withoutVault]);
      },
    );

    test('a newer call during the retry: the retry is not sent again after '
        'it', () async {
      final src = _Src();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: src,
        log: FakeLog(),
      );
      addTearDown(h.dispose);
      final remove = h.setCaptureIgnored(withoutVault);
      src.answerNext(false);
      await pumpEventQueue(); // the retry of the removal is on its way
      final undo = h.setCaptureIgnored(withVault);
      while (src.waiting > 0) {
        src.answerNext(true);
        await pumpEventQueue();
      }
      await remove;
      await undo;
      expect(src.received.last, withVault);
    });
  });
}
