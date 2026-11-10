// M1.6 tester, round 3: interleavings of pause, resume and tick against a
// native side whose answers are controlled call by call (R1), launch and
// timer failures (R2), notifications across midnight (R8), and a native call
// that never answers.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;

/// Each call gets its own completer; the test answers in any order.
class _Native {
  final received = <int>[];
  final pending = <(int, Completer<bool>)>[];
  bool auto = true;
  bool answer = true;

  Future<bool> call(int until) {
    received.add(until);
    if (auto) return Future.value(answer);
    final c = Completer<bool>();
    pending.add((until, c));
    return c.future;
  }

  Future<void> answerFirst([bool ok = true]) async {
    pending.removeAt(0).$2.complete(ok);
    await pumpEventQueue();
  }

  Future<void> drain() async {
    await pumpEventQueue();
    while (pending.isNotEmpty) {
      await answerFirst();
    }
  }

  /// What native code holds: the last value received.
  int get has => received.last;
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
  group('R1: interleavings end with native holding Dart\'s state', () {
    test('rapid pause, resume, pause: native sees them in order and ends '
        'paused', () async {
      final h = _H();
      h.service.load();
      await pumpEventQueue();
      h.native.auto = false;
      h.native.received.clear();
      final a = h.service.pause(PauseLength.quarterHour);
      final b = h.service.resume();
      final c = h.service.pause(PauseLength.hour);
      await h.native.drain();
      await Future.wait([a, b, c]);
      expect(h.service.pausedUntil, h.now + 60 * _min);
      expect(h.native.has, h.service.pausedUntil);
      expect(h.native.received.first, h.now + 15 * _min);
      expect(h.native.received[1], 0);
    });

    test('a tick ends an expired pause while the user pauses again: native '
        'ends on the new pause', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.now += 20 * _min;
      h.native.auto = false;
      final tick = h.service.tick(); // sends 0, waits
      final p = h.service.pause(PauseLength.hour);
      await h.native.drain();
      await Future.wait([tick, p]);
      expect(h.service.isPaused, isTrue);
      expect(h.native.has, h.service.pausedUntil);
    });

    test(
      'a resume while a clock-back cut is waiting: both end not paused',
      () async {
        final h = _H();
        h.service.load();
        await h.service.pause(PauseLength.hour);
        h.now -= 3 * 60 * _min;
        h.native.auto = false;
        final tick = h.service.tick(); // cut, sends the cut value
        final r = h.service.resume();
        await h.native.drain();
        await Future.wait([tick, r]);
        expect(h.service.isPaused, isFalse);
        expect(h.native.has, 0);
        expect(h.settings[historyPausedSetting], '0');
      },
    );

    test('a resume that waits while a tick cuts after it: native is put '
        'back to 0', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.hour);
      h.native.auto = false;
      final r = h.service.resume(); // waits for its answer
      h.now -= 3 * 60 * _min;
      final tick = h.service.tick(); // still sees the old pause, cuts, sends
      await h.native.drain();
      await Future.wait([r, tick]);
      expect(h.service.isPaused, isFalse);
      expect(h.native.has, 0, reason: 'native must not stay paused');
    });

    test('a pause after an expired pause was ended by a tick that has not '
        'answered yet', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.now += 16 * _min;
      h.native.auto = false;
      final tick = h.service.tick();
      await pumpEventQueue();
      final p = h.service.pause(PauseLength.untilResumed);
      await h.native.drain();
      await Future.wait([tick, p]);
      expect(h.service.untilResumed, isTrue);
      expect(h.native.has, -1);
      expect(h.settings[historyPausedSetting], '-1');
    });

    test('many ticks while one call waits do not pile up calls', () async {
      final h = _H();
      h.service.load();
      await pumpEventQueue();
      h.native.auto = false;
      h.native.received.clear();
      final p = h.service.pause(PauseLength.hour);
      for (var i = 0; i < 5; i++) {
        unawaited(h.service.tick());
      }
      await h.native.drain();
      await p;
      expect(h.service.isPaused, isTrue);
      expect(h.native.has, h.service.pausedUntil);
    });

    test(
      'a failed first call in the queue does not block the next one',
      () async {
        final h = _H();
        h.service.load();
        await pumpEventQueue();
        h.native.auto = false;
        final a = h.service.pause(PauseLength.hour);
        final b = h.service.pause(PauseLength.quarterHour);
        await pumpEventQueue();
        await h.native.answerFirst(false);
        await h.native.drain();
        expect(await a, isFalse);
        expect(await b, isTrue);
        expect(h.service.pausedUntil, h.now + 15 * _min);
      },
    );
  });

  group('R1: a native call that never answers', () {
    test('the user can still pause within a few seconds (a stuck call must '
        'not freeze the Pause button for good)', () async {
      final h = _H();
      h.native.auto = false;
      h.service.load(); // this call never answers
      final p = h.service.pause(PauseLength.hour);
      final result = await p.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      expect(result, isTrue);
    });
  });

  group('R2: launch and timer failures', () {
    test('a launch send that fails: retried on every tick, apply error '
        'shown after the first failed retry, stays after it works', () async {
      final h = _H(stored: '-1');
      h.native.answer = false;
      h.service.load();
      await pumpEventQueue();
      expect(h.service.error, isNull, reason: 'not shown before a retry');
      h.native.received.clear();
      await h.service.tick();
      expect(h.service.error, PauseError.apply);
      await h.service.tick();
      await h.service.tick();
      expect(h.native.received, [-1, -1, -1], reason: 'every tick retries');
      h.native.answer = true;
      await h.service.tick();
      h.native.received.clear();
      await h.service.tick();
      expect(
        h.native.received,
        isEmpty,
        reason: 'no more retries once in step',
      );
      expect(h.service.error, PauseError.apply, reason: 'until the user acts');
      await h.service.resume();
      expect(h.service.error, isNull);
    });

    test('a user\'s own failed pause is retried once only', () async {
      final h = _H();
      h.service.load();
      await pumpEventQueue();
      h.native.answer = false;
      await h.service.pause(PauseLength.hour);
      h.native.received.clear();
      for (var i = 0; i < 4; i++) {
        await h.service.tick();
      }
      expect(h.native.received, hasLength(1));
    });

    test('a timer end whose send fails shows the apply error and retries '
        'every tick', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.native.answer = false;
      h.now += 16 * _min;
      await h.service.tick();
      await h.service.tick();
      expect(h.service.error, PauseError.apply);
      h.native.received.clear();
      await h.service.tick();
      await h.service.tick();
      expect(h.native.received, [0, 0]);
    });

    test('settings that cannot be read: paused until resumed, error shown, '
        'the stored value is not overwritten', () async {
      var writes = 0;
      final s = PauseService(
        setNativePause: (_) async => true,
        readSetting: (_) => throw StateError('locked'),
        writeSetting: (_, _) {
          writes++;
          return true;
        },
        log: FakeLog(),
        persists: true,
        clock: () => 1_762_790_400_000,
      )..load();
      addTearDown(s.dispose);
      await pumpEventQueue();
      expect(s.untilResumed, isTrue);
      expect(s.error, PauseError.apply);
      expect(writes, 0);
      await s.tick(); // a tick must not "settle" it away or write
      expect(s.untilResumed, isTrue);
      expect(writes, 0);
    });

    test('a garbled value is not paused and shows no error', () async {
      for (final bad in ['garbage', '', '-9', '1.5']) {
        final h = _H(stored: bad);
        h.service.load();
        await pumpEventQueue();
        expect(h.service.isPaused, isFalse, reason: bad);
        expect(h.service.error, isNull, reason: bad);
      }
    });
  });

  group('R8: notifications only for visible changes', () {
    test('quiet ticks do not notify; the tick counter still moves', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.hour);
      var n = 0;
      h.service.addListener(() => n++);
      final before = h.service.ticks.value;
      for (var i = 0; i < 5; i++) {
        h.now += 1000;
        await h.service.tick();
      }
      expect(n, 0);
      expect(h.service.ticks.value, before + 5);
    });

    test(
      'a tick that ends the pause, or cuts it, notifies once each',
      () async {
        final h = _H();
        h.service.load();
        await h.service.pause(PauseLength.hour);
        var n = 0;
        h.service.addListener(() => n++);
        h.now -= 2 * 60 * _min;
        await h.service.tick(); // cut: the shown time changes
        expect(n, 1);
        h.now += 70 * _min;
        await h.service.tick(); // end
        expect(n, 2);
        await h.service.tick();
        expect(n, 2);
      },
    );

    test('midnight: "tomorrow 00:05" turns into "00:05" with one '
        'notification, and not before', () async {
      final h = _H();
      h.now = DateTime(2026, 11, 10, 23, 50).millisecondsSinceEpoch;
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      final end = h.service.endsAt!;
      expect(
        formatPauseEnd(end, h.service.now, use24Hour: true),
        'tomorrow 00:05',
      );
      var n = 0;
      h.service.addListener(() => n++);
      h.now = DateTime(2026, 11, 10, 23, 59, 59).millisecondsSinceEpoch;
      await h.service.tick();
      expect(n, 0);
      h.now = DateTime(2026, 11, 11, 0, 0, 1).millisecondsSinceEpoch;
      await h.service.tick();
      expect(n, 1);
      expect(
        formatPauseEnd(h.service.endsAt!, h.service.now, use24Hour: true),
        '00:05',
      );
      await h.service.tick();
      expect(n, 1);
    });

    test('an until-resumed pause never notifies on midnight', () async {
      final h = _H();
      h.now = DateTime(2026, 11, 10, 23, 59, 50).millisecondsSinceEpoch;
      h.service.load();
      await h.service.pause(PauseLength.untilResumed);
      var n = 0;
      h.service.addListener(() => n++);
      h.now += 30 * 1000;
      await h.service.tick();
      expect(n, 0);
    });

    test('an error appearing on a tick notifies', () async {
      final h = _H(stored: '-1');
      h.native.answer = false;
      h.service.load();
      await pumpEventQueue();
      var n = 0;
      h.service.addListener(() => n++);
      await h.service.tick();
      expect(n, 1);
      expect(h.service.error, PauseError.apply);
    });
  });
}
