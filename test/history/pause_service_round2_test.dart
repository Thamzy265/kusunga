// M1.6 fix round 2 (reviewer R1, R2, R8): PauseService keeps native code in
// step when a tick runs while a pause or resume waits for its native call,
// surfaces a launch or timer send that stays out of step, and notifies only
// when what the user sees changes.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;

/// A native side whose answers come when the test says so. Native code
/// applies each value when the call arrives (the channel keeps call order),
/// so [received] is native's state, call by call.
class _Native {
  final received = <int>[];
  final _pending = <Completer<bool>>[];
  var manual = false;

  Future<bool> call(int until) {
    received.add(until);
    if (!manual) return Future.value(true);
    final c = Completer<bool>();
    _pending.add(c);
    return c.future;
  }

  /// Answers every waiting call with true, oldest first, until none is
  /// left (a call can lead to another one).
  Future<void> drain() async {
    await pumpEventQueue();
    while (_pending.isNotEmpty) {
      _pending.removeAt(0).complete(true);
      await pumpEventQueue();
    }
  }
}

/// A store whose settings can't be read, like a locked database.
class _UnreadableSettings extends FlakyStore {
  _UnreadableSettings() : super(MemoryHistoryStore());

  @override
  String? readSetting(String key) => throw StateError('database locked');
}

class _H {
  _H({String? stored}) {
    if (stored != null) settings[historyPausedSetting] = stored;
  }

  var now = 1_762_790_400_000;
  final settings = <String, String>{};
  final native = _Native();
  final log = FakeLog();

  late final service = PauseService(
    setNativePause: native.call,
    readSetting: (k) => settings[k],
    writeSetting: (k, v) {
      settings[k] = v;
      return true;
    },
    log: log,
    persists: true,
    clock: () => now,
  );
}

void main() {
  group('R1: a tick during a pause or resume leaves native in step', () {
    test('pause while an expired timed pause is ended by a tick', () async {
      final h = _H();
      h.settings[historyPausedSetting] = '${h.now + 15 * _min}';
      h.service.load();
      await pumpEventQueue();
      // The timed pause ended; no tick has run yet.
      h.now += 20 * _min;
      h.native.manual = true;
      final pause = h.service.pause(PauseLength.untilResumed);
      final tick = h.service.tick(); // window activation
      await h.native.drain();
      expect(await pause, isTrue);
      await tick;
      expect(h.service.pausedUntil, -1);
      expect(h.service.isPaused, isTrue);
      expect(
        h.native.received.last,
        h.service.pausedUntil,
        reason: 'native must not be unpaused while the UI says paused',
      );
    });

    test('a 15-minute pause in the same race', () async {
      final h = _H();
      h.settings[historyPausedSetting] = '${h.now + 15 * _min}';
      h.service.load();
      await pumpEventQueue();
      h.now += 20 * _min;
      h.native.manual = true;
      final pause = h.service.pause(PauseLength.quarterHour);
      final tick = h.service.tick();
      await h.native.drain();
      await pause;
      await tick;
      expect(h.service.pausedUntil, h.now + 15 * _min);
      expect(h.native.received.last, h.service.pausedUntil);
    });

    test(
      'resume while a tick cuts a pause after the clock went back',
      () async {
        final h = _H();
        h.settings[historyPausedSetting] = '${h.now + 30 * _min}';
        h.service.load();
        await pumpEventQueue();
        // The clock is set back 2 hours: the end is now more than 60 min away.
        h.now -= 120 * _min;
        h.native.manual = true;
        final resume = h.service.resume();
        final tick = h.service.tick();
        await h.native.drain();
        expect(await resume, isTrue);
        await tick;
        expect(h.service.pausedUntil, 0);
        expect(h.service.isPaused, isFalse);
        expect(
          h.native.received.last,
          0,
          reason: 'native must not stay paused while the UI says recording',
        );
      },
    );

    test('with nothing in flight, a pause makes exactly one call', () async {
      final h = _H();
      h.service.load();
      await pumpEventQueue();
      h.native.received.clear();
      await h.service.pause(PauseLength.hour);
      await h.service.tick();
      expect(h.native.received, [h.service.pausedUntil]);
    });
  });

  group('R2: a launch or timer send that stays out of step is shown', () {
    late int now;
    late bool nativeOk;
    late List<int> sent;
    late Map<String, String> settings;
    late FakeLog log;
    String? Function(String) read = (k) => null;

    PauseService make() {
      final p = PauseService(
        setNativePause: (until) async {
          if (!nativeOk) return false;
          sent.add(until);
          return true;
        },
        readSetting: (k) => read(k),
        writeSetting: (k, v) {
          settings[k] = v;
          return true;
        },
        log: log,
        persists: true,
        clock: () => now,
      );
      addTearDown(p.dispose);
      return p;
    }

    setUp(() {
      now = 1_762_790_400_000;
      nativeOk = true;
      sent = [];
      settings = {};
      log = FakeLog();
      read = (k) => settings[k];
    });

    test('load fails, the retry fails: the apply error shows, and later '
        'ticks keep retrying until native has the pause', () async {
      settings[historyPausedSetting] = '-1';
      nativeOk = false;
      final p = make()..load();
      await pumpEventQueue();
      expect(p.error, isNull, reason: 'not yet: the retry comes first');
      await p.tick(); // the retry fails too
      expect(p.error, PauseError.apply);
      await p.tick();
      await p.tick();
      expect(p.error, PauseError.apply);
      nativeOk = true;
      await p.tick();
      expect(sent, [-1], reason: 'retried on a later tick, and it worked');
      await p.tick();
      expect(sent, [-1], reason: 'in step now: no more calls');
      expect(p.isPaused, isTrue);
    });

    test('load fails once, the retry works: no error', () async {
      settings[historyPausedSetting] = '-1';
      nativeOk = false;
      final p = make()..load();
      await pumpEventQueue();
      nativeOk = true;
      await p.tick();
      expect(sent, [-1]);
      expect(p.error, isNull);
    });

    test('a timer end that native misses twice shows the apply error and '
        'is retried on later ticks', () async {
      final p = make()..load();
      await pumpEventQueue();
      await p.pause(PauseLength.quarterHour);
      sent.clear();
      nativeOk = false;
      now += 20 * _min;
      await p.tick(); // the timer end: fails
      await p.tick(); // the retry: fails
      expect(p.error, PauseError.apply);
      await p.tick();
      nativeOk = true;
      await p.tick();
      expect(sent, [0]);
    });

    test('a settings read error at launch stays paused until resume, shows '
        'the apply error, and tells native -1', () async {
      read = (_) => throw StateError('database locked');
      final p = make()..load();
      await pumpEventQueue();
      expect(p.untilResumed, isTrue);
      expect(p.isPaused, isTrue);
      expect(p.error, PauseError.apply);
      expect(sent, [-1]);
      expect(settings, isEmpty, reason: 'an unread value is not overwritten');
      // Resume works as usual and clears the error.
      expect(await p.resume(), isTrue);
      expect(p.error, isNull);
      expect(p.isPaused, isFalse);
    });
  });

  test('R2 through HistoryService: a settings read error at start pauses '
      'until resume and shows the apply error', () async {
    final source = FakeClipboardSource();
    final log = FakeLog();
    final h = HistoryService(
      store: _UnreadableSettings(),
      source: source,
      log: log,
    );
    addTearDown(h.dispose);
    h.start();
    await pumpEventQueue();
    expect(h.pause.untilResumed, isTrue);
    expect(h.pause.error, PauseError.apply);
    expect(source.sentPause, -1);
    expect(log.codes, contains(LogCode.readFailed));
  });
}
