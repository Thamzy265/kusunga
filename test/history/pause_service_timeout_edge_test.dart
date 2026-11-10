// M1.6 tester, round 4: the native-call timeout (nativeTimeout, 2 s), the job
// queue (user calls ahead of a waiting background send) and late answers.
// Fake time: testWidgets' clock moves only with pump(duration).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;
const _to = PauseService.nativeTimeout;

class _Native {
  final received = <int>[];
  final pending = <(int, Completer<bool>)>[];

  /// Which calls hang: by index of arrival. Others answer true at once.
  final hang = <int>{};
  bool hangAll = false;

  Future<bool> call(int until) {
    final i = received.length;
    received.add(until);
    if (hangAll || hang.contains(i)) {
      final c = Completer<bool>();
      pending.add((until, c));
      return c.future;
    }
    return Future.value(true);
  }

  int get has => received.last;
}

class _H {
  _H({String? stored}) {
    if (stored != null) settings[historyPausedSetting] = stored;
  }

  var now = 1_762_790_400_000;
  final settings = <String, String>{};
  final native = _Native();
  late final service = PauseService(
    setNativePause: native.call,
    readSetting: (k) => settings[k],
    writeSetting: (k, v) {
      settings[k] = v;
      return true;
    },
    log: FakeLog(),
    persists: true,
    clock: () => now,
  );
}

void main() {
  testWidgets('a late "true" with an old value after the timeout is ignored: '
      'the newer user pause stays, native keeps the newer value', (
    tester,
  ) async {
    final h = _H();
    h.native.hang.add(1); // load is call 0 (answers), the first pause hangs
    h.service.load();
    await tester.pump();
    bool? first;
    unawaited(h.service.pause(PauseLength.hour).then((v) => first = v));
    await tester.pump(_to + const Duration(milliseconds: 1));
    expect(first, isFalse);
    final second = h.service.pause(PauseLength.quarterHour);
    await tester.pump();
    expect(await second, isTrue);
    final want = h.service.pausedUntil;
    // The old call answers late, after the newer one worked.
    h.native.pending.first.$2.complete(true);
    await tester.pump(const Duration(seconds: 1));
    expect(h.service.pausedUntil, want);
    expect(h.service.isPaused, isTrue);
    expect(h.native.has, want, reason: 'native keeps the newer value');
    await tester.pump(const Duration(seconds: 40));
  });

  testWidgets('a user pause that timed out but was applied late by native '
      'is put right by the next tick (native resumed to match Dart)', (
    tester,
  ) async {
    final h = _H();
    h.native.hang.add(1);
    h.service.load();
    await tester.pump();
    unawaited(h.service.pause(PauseLength.untilResumed));
    await tester.pump(_to + const Duration(milliseconds: 1));
    expect(h.service.isPaused, isFalse);
    expect(h.service.error, PauseError.apply);
    h.native.pending.first.$2.complete(true); // late: native did apply -1
    await tester.pump();
    unawaited(h.service.tick());
    await tester.pump(const Duration(seconds: 1));
    expect(h.native.has, 0, reason: 'native must not stay paused alone');
  });

  testWidgets('a user pause behind a stuck background call waits at most '
      'one timeout, then is sent and works', (tester) async {
    final h = _H();
    h.native.hang.add(0); // the launch send hangs
    h.service.load();
    await tester.pump();
    bool? r;
    final t0 = tester.binding.clock.now();
    DateTime? done;
    unawaited(
      h.service.pause(PauseLength.hour).then((v) {
        r = v;
        done = tester.binding.clock.now();
      }),
    );
    await tester.pump(_to + const Duration(milliseconds: 50));
    expect(r, isTrue);
    expect(
      done!.difference(t0),
      lessThanOrEqualTo(_to + const Duration(milliseconds: 50)),
    );
    expect(h.native.has, h.service.pausedUntil);
  });

  testWidgets('pause then resume while every call hangs: both fail, each '
      'after its own timeout, nothing changes, resume error wins', (
    tester,
  ) async {
    final h = _H();
    h.native.hangAll = true;
    h.service.load();
    bool? p, r;
    unawaited(h.service.pause(PauseLength.hour).then((v) => p = v));
    unawaited(h.service.resume().then((v) => r = v));
    await tester.pump(_to * 3);
    expect(p, isFalse);
    expect(r, isFalse);
    expect(h.service.isPaused, isFalse);
    expect(h.service.error, PauseError.resume);
    expect(h.settings[historyPausedSetting], isNull);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('a user call is never held by more than the background call '
      'ahead of it plus its own timeout', (tester) async {
    final h = _H();
    h.native.hangAll = true;
    h.service.load(); // background call 0 stuck from t = 0
    await tester.pump(const Duration(milliseconds: 500));
    final t0 = tester.binding.clock.now();
    DateTime? done;
    unawaited(
      h.service.pause(PauseLength.hour).then((_) {
        done = tester.binding.clock.now();
      }),
    );
    await tester.pump(_to * 3);
    expect(done, isNotNull);
    // Waits for call 0 (1.5 s left) and then its own call (2 s).
    expect(done!.difference(t0), lessThanOrEqualTo(_to * 2));
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('a timeout on the launch send, then the timed pause ends: the '
      'tick resumes native and shows no error', (tester) async {
    final h = _H();
    h.settings[historyPausedSetting] = '${h.now + 10 * _min}';
    h.native.hang.add(0);
    h.service.load();
    await tester.pump(_to + const Duration(milliseconds: 1));
    h.now += 11 * _min;
    unawaited(h.service.tick());
    await tester.pump(const Duration(seconds: 1));
    expect(h.service.isPaused, isFalse);
    expect(h.native.has, 0);
    expect(h.settings[historyPausedSetting], '0');
    expect(h.service.error, isNull);
  });

  testWidgets('dispose with calls running and queued: no more native calls '
      'start, nothing throws, no timer is left', (tester) async {
    final h = _H();
    h.native.hangAll = true;
    h.service.load();
    unawaited(h.service.pause(PauseLength.hour));
    unawaited(h.service.resume());
    await tester.pump();
    final sentAtDispose = h.native.received.length;
    h.service.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(
      h.native.received.length,
      sentAtDispose,
      reason: 'queued calls must not reach native after dispose',
    );
  });

  testWidgets('background requests share one waiting send: 20 ticks behind a '
      'stuck call add at most one call', (tester) async {
    final h = _H();
    h.native.hangAll = true;
    h.service.load();
    await tester.pump();
    final before = h.native.received.length;
    h.now += 0;
    for (var i = 0; i < 20; i++) {
      unawaited(h.service.tick());
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.native.received.length - before, 0, reason: 'still behind call 0');
    await tester.pump(_to + const Duration(milliseconds: 10));
    // Call 0 timed out: exactly one shared send follows, however many ticks.
    expect(h.native.received.length - before, lessThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('the waiting background send reads Dart state when it starts, '
      'not when it was asked', (tester) async {
    final h = _H();
    h.native.hang.add(0);
    h.service.load();
    await tester.pump();
    // A tick asks for a send while the launch call is stuck...
    unawaited(h.service.tick());
    await tester.pump();
    // ...then the user pauses (goes ahead of the waiting send).
    unawaited(h.service.pause(PauseLength.untilResumed));
    await tester.pump(_to + const Duration(milliseconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(h.service.untilResumed, isTrue);
    expect(h.native.has, -1, reason: 'the last value native got is current');
  });
}
