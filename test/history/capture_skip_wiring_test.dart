// M1.6 wiring on the Dart side (design note "Pause clock" and option A):
// the pause and the ignore list reach the native watcher before it starts,
// the new events are logged as codes only, and a copy that still arrives
// while Dart knows history is paused is not saved.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/clipboard/clipboard_source.dart';
import 'package:kusunga/history/history_opener.dart' show HistoryNotice;
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/shortcuts/ignored_apps.dart';

import '../support/fakes.dart';

void main() {
  late FakeClipboardSource source;
  late FakeLog log;
  late MemoryHistoryStore store;
  var now = 1_762_790_400_000;

  setUp(() {
    source = FakeClipboardSource();
    log = FakeLog();
    store = MemoryHistoryStore();
    now = 1_762_790_400_000;
  });

  HistoryService start() =>
      HistoryService(store: store, source: source, log: log, clock: () => now)
        ..start();

  test('history_paused_until is a stored setting', () {
    expect(HistoryStore.storedSettingKeys, contains(historyPausedSetting));
  });

  test('the pause, then the ignore list, are sent before listening', () {
    final h = start();
    expect(source.calls.take(3), [
      'setCapturePause',
      'setCaptureIgnored',
      'listen',
    ]);
    expect(source.sentPause, 0);
    expect(source.sentIgnored, [for (final a in presetIgnoredApps) a.appId]);
    h.dispose();
  });

  test('a saved pause is read before the watcher starts (D3 A)', () {
    store.writeSetting(historyPausedSetting, '-1');
    final h = start();
    expect(source.sentPause, -1);
    expect(h.pause.isPaused, isTrue);
    expect(
      source.calls.indexOf('setCapturePause'),
      lessThan(source.calls.indexOf('listen')),
    );
    h.dispose();
  });

  test('ignoredApp is logged as a code and nothing is saved', () {
    final h = start();
    source.controller.add(const ClipboardSkipped(SkipReason.ignoredApp));
    expect(log.codes, [LogCode.captureSkippedIgnoredApp]);
    expect(log.details, [null]);
    expect(h.items, isEmpty);
    h.dispose();
  });

  test('sourceUnknown is counted, and the copy after it is saved as today', () {
    final h = start();
    source.controller.add(const ClipboardSourceUnknown());
    source.copy('hello');
    expect(log.codes, [LogCode.captureSourceUnknown]);
    expect(h.items.single.preview, 'hello');
    h.dispose();
  });

  test(
    'a copy that arrives while paused is not saved (Dart checks again)',
    () async {
      final h = start();
      await h.pause.pause(PauseLength.quarterHour);
      source.copy('during the pause');
      expect(h.items, isEmpty);
      now += 15 * 60 * 1000;
      source.copy('after');
      expect(h.items.single.preview, 'after');
      h.dispose();
    },
  );

  test('pausing writes the setting in the history store', () async {
    final h = start();
    await h.pause.pause(PauseLength.untilResumed);
    expect(store.readSetting(historyPausedSetting), '-1');
    await h.pause.resume();
    expect(store.readSetting(historyPausedSetting), '0');
    h.dispose();
  });

  test('memory-only: the pause applies but will not last', () async {
    final h = HistoryService(
      store: store,
      source: source,
      log: log,
      notices: const {HistoryNotice.memoryOnly},
    )..start();
    expect(h.pause.willLast, isFalse);
    expect(await h.pause.pause(PauseLength.hour), isTrue);
    expect(h.pause.isPaused, isTrue);
    h.dispose();
  });

  test('setCaptureIgnored forwards the list to the watcher', () async {
    final h = start();
    await h.setCaptureIgnored(['keepass.exe']);
    expect(source.sentIgnored, ['keepass.exe']);
    h.dispose();
  });
}
