// M1.6 tester, round 3: R3 (an older ignore-list retry never follows a newer
// list) and R4 (presets, never an empty list, when the list can't be read).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';

import '../support/fakes.dart';

class _Gated extends FakeClipboardSource {
  final sent = <List<String>>[];
  final waiting = <Completer<bool>>[];
  bool gated = true;

  @override
  Future<bool> setCaptureIgnored(List<String> appIds) {
    sent.add(List.of(appIds));
    if (!gated) return Future.value(true);
    final c = Completer<bool>();
    waiting.add(c);
    return c.future;
  }
}

class _Throwing extends MemoryIgnoredAppStore {
  @override
  List<IgnoredApp> list() => throw StateError('unreadable');
}

void main() {
  HistoryService make(_Gated src, FakeLog log) {
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: src,
      log: log,
    );
    addTearDown(h.dispose);
    return h;
  }

  test('A fails, B is asked while A waits: A is never retried, B is sent, '
      'nothing is logged for A', () async {
    final src = _Gated();
    final log = FakeLog();
    final h = make(src, log);
    final a = h.setCaptureIgnored(['a']);
    await pumpEventQueue();
    final b = h.setCaptureIgnored(['b']);
    await pumpEventQueue();
    src.waiting[0].complete(false); // A fails
    src.waiting[1].complete(true); // B works
    await pumpEventQueue();
    expect(await a, isFalse);
    expect(await b, isTrue);
    expect(src.sent, [
      ['a'],
      ['b'],
    ]);
    expect(log.codes, isEmpty);
  });

  test('A fails, its retry is already in flight when B is asked: the last '
      'list sent is still B', () async {
    final src = _Gated();
    final h = make(src, FakeLog());
    final a = h.setCaptureIgnored(['a']);
    await pumpEventQueue();
    src.waiting[0].complete(false);
    await pumpEventQueue(); // A's retry is now sent
    expect(src.sent.length, 2);
    final b = h.setCaptureIgnored(['b']);
    await pumpEventQueue();
    // Answers arrive in call order on the real channel.
    src.waiting[1].complete(true);
    src.waiting[2].complete(true);
    await Future.wait([a, b]);
    expect(src.sent.last, ['b']);
  });

  test(
    'the newest list failing twice still logs one code, no app id',
    () async {
      final src = _Gated()..gated = false;
      final log = FakeLog();
      final h = make(src, log);
      final srcFail = _AlwaysFail();
      final h2 = HistoryService(
        store: MemoryHistoryStore(),
        source: srcFail,
        log: log,
      );
      addTearDown(h2.dispose);
      expect(await h2.setCaptureIgnored(['com.secret.vault']), isFalse);
      expect(log.codes, [LogCode.captureIgnoredSendFailed]);
      expect(log.details, [null]);
      expect(srcFail.tries, 2);
      expect(h.items, isEmpty);
    },
  );

  test('R4: an unreadable list at start sends every preset, not []', () {
    final src = _Gated()..gated = false;
    final log = FakeLog();
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: src,
      log: log,
      ignoredAppStore: _Throwing(),
    )..start();
    addTearDown(h.dispose);
    expect(src.sent.single, [for (final p in presetIgnoredApps) p.appId]);
    expect(src.sent.single, isNotEmpty);
    expect(log.codes, contains(LogCode.readFailed));
  });
}

class _AlwaysFail extends FakeClipboardSource {
  int tries = 0;
  @override
  Future<bool> setCaptureIgnored(List<String> appIds) async {
    tries++;
    return false;
  }
}
