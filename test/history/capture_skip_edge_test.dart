// M1.6 tester: start-up race, native-out-of-step and failure paths on the
// Dart side of capture skips (docs/design/sensitive-content.md "Pause
// clock", "Failure plan"; ADR 0005).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';

import '../support/fakes.dart';

/// A source that emits a copy the moment the event channel is listened to,
/// like a watcher that starts and sees a copy already on the clipboard.
class _EagerSource extends FakeClipboardSource {
  _EagerSource(this.first) {
    controller.onListen = () {
      calls.add('listen');
      scheduleMicrotask(() => controller.add(ClipboardText(first)));
    };
  }
  final String first;
}

class _ThrowingIgnored extends MemoryIgnoredAppStore {
  @override
  List<IgnoredApp> list() => throw StateError('unreadable');
}

void main() {
  var now = 1_762_790_400_000;
  setUp(() => now = 1_762_790_400_000);

  test('a copy that arrives right at listen is dropped while a saved pause '
      'is on (start-up race)', () async {
    final store = MemoryHistoryStore()
      ..writeSetting(historyPausedSetting, '-1');
    final source = _EagerSource('secret at launch');
    final h = HistoryService(
      store: store,
      source: source,
      log: FakeLog(),
      clock: () => now,
    )..start();
    await pumpEventQueue();
    expect(h.items, isEmpty);
    expect(source.calls.first, 'setCapturePause');
    expect(source.sentPause, -1);
    h.dispose();
  });

  test('the pause and the list go out before listen, even when the list '
      'is empty', () {
    final source = FakeClipboardSource();
    final store = MemoryIgnoredAppStore();
    for (final p in presetIgnoredApps) {
      store.remove(p.appId);
    }
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
      ignoredAppStore: store,
    )..start();
    expect(source.calls.take(3), [
      'setCapturePause',
      'setCaptureIgnored',
      'listen',
    ]);
    expect(source.sentIgnored, isEmpty);
    h.dispose();
  });

  test('native refused the pause at start: Dart still drops copies, and a '
      'tick sends it again', () async {
    final source = FakeClipboardSource()..pauseAnswer = false;
    final store = MemoryHistoryStore()
      ..writeSetting(historyPausedSetting, '-1');
    final h = HistoryService(
      store: store,
      source: source,
      log: FakeLog(),
      clock: () => now,
    )..start();
    await pumpEventQueue();
    source.copy('while native is out of step');
    expect(h.items, isEmpty);
    source.pauseAnswer = true;
    await h.pause.tick();
    expect(source.sentPause, -1);
    h.dispose();
  });

  test('a pause that ended is not dropped by Dart even before a tick', () {
    final source = FakeClipboardSource();
    final store = MemoryHistoryStore()
      ..writeSetting(historyPausedSetting, '${now + 1000}');
    final h = HistoryService(
      store: store,
      source: source,
      log: FakeLog(),
      clock: () => now,
    )..start();
    now += 1000; // exactly the end time
    source.copy('after the end');
    expect(h.items.single.preview, 'after the end');
    h.dispose();
  });

  test('ignoredApp and paused never reach the store, however many arrive', () {
    final source = FakeClipboardSource();
    final store = MemoryHistoryStore();
    final h = HistoryService(store: store, source: source, log: FakeLog())
      ..start();
    for (var i = 0; i < 50; i++) {
      source.controller.add(const ClipboardSkipped(SkipReason.ignoredApp));
    }
    expect(h.items, isEmpty);
    expect(store.count, 0);
    h.dispose();
  });

  test('every log line from skips is a code with no detail, or 15, 60, -1, '
      '0, 1', () async {
    final source = FakeClipboardSource();
    final log = FakeLog();
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      clock: () => now,
    )..start();
    source.controller.add(const ClipboardSkipped(SkipReason.ignoredApp));
    source.controller.add(const ClipboardSourceUnknown());
    await h.pause.pause(PauseLength.hour);
    await h.pause.resume();
    for (var i = 0; i < log.codes.length; i++) {
      final code = log.codes[i];
      final d = log.details[i];
      switch (code) {
        case LogCode.captureSkippedIgnoredApp:
        case LogCode.captureSourceUnknown:
          expect(d, isNull);
        case LogCode.capturePaused:
          expect({15, 60, -1}, contains(d));
        case LogCode.captureResumed:
          expect({0, 1}, contains(d));
        default:
          fail('unexpected log code $code');
      }
    }
    h.dispose();
  });

  test('a throwing ignore-list store: logs readFailed and does not crash '
      'start-up', () {
    final source = FakeClipboardSource();
    final log = FakeLog();
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: log,
      ignoredAppStore: _ThrowingIgnored(),
    )..start();
    expect(log.codes, contains(LogCode.readFailed));
    expect(source.calls, contains('listen'));
    h.dispose();
  });

  test('a native setCaptureIgnored that throws is swallowed', () async {
    final source = _ThrowingSource();
    final h = HistoryService(
      store: MemoryHistoryStore(),
      source: source,
      log: FakeLog(),
    )..start();
    await pumpEventQueue();
    expect(await h.setCaptureIgnored(['a']), isFalse);
    h.dispose();
  });

  test(
    'closing the service stops the pause service (no tick after close)',
    () async {
      final source = FakeClipboardSource();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: source,
        log: FakeLog(),
      )..start();
      h.pause.startTicking(listenToLifecycle: false);
      var n = 0;
      h.pause.addListener(() => n++);
      await h.close();
      await h.pause.tick();
      expect(n, 0);
    },
  );
}

class _ThrowingSource extends FakeClipboardSource {
  @override
  Future<bool> setCaptureIgnored(List<String> appIds) async =>
      throw StateError('channel');
}
