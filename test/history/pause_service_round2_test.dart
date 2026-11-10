// M1.6 fix round 2 (reviewer R1, R2, R8): PauseService keeps native code in
// step when a tick runs while a pause or resume waits for its native call,
// surfaces a launch or timer send that stays out of step, and notifies only
// when what the user sees changes.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';

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
}
