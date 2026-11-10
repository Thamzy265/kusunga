// M1.6 fix round 3 (reviewer N2, tester N1): a native call that never
// answers counts as a failure after PauseService.nativeTimeout, so the
// normal retry and error rules apply and the chain moves on (lead decision
// 2026-11-10, option b). A user's pause or resume waits at most one timeout
// behind a stuck background call, and ticks queue at most one background
// send. Fake time: testWidgets' clock moves only with pump(duration).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';

import '../support/fakes.dart';

/// A native side that answers each call with [answerFor], or never when
/// that gives null.
class _Native {
  final received = <int>[];
  bool? Function(int until) answerFor = (_) => true;

  Future<bool> call(int until) {
    received.add(until);
    final answer = answerFor(until);
    if (answer == null) return Completer<bool>().future; // never answers
    return Future.value(answer);
  }
}

PauseService _make(_Native native, {String? stored}) {
  final settings = <String, String>{historyPausedSetting: ?stored};
  return PauseService(
    setNativePause: native.call,
    readSetting: (k) => settings[k],
    writeSetting: (k, v) {
      settings[k] = v;
      return true;
    },
    log: FakeLog(),
    persists: true,
    clock: () => 1_762_790_400_000,
  );
}

void main() {
  test('the timeout is about 2 s', () {
    expect(PauseService.nativeTimeout, const Duration(seconds: 2));
  });

  testWidgets('a pause whose call never answers fails after the timeout, '
      'with the apply error', (tester) async {
    final native = _Native();
    final p = _make(native)..load();
    await tester.pump();
    native.answerFor = (_) => null;
    bool? result;
    unawaited(p.pause(PauseLength.hour).then((v) => result = v));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(result, isNull, reason: 'still within the timeout');
    await tester.pump(const Duration(milliseconds: 200));
    expect(result, isFalse);
    expect(p.error, PauseError.apply);
    expect(p.isPaused, isFalse);
  });

  testWidgets('a user pause goes ahead of a waiting background send, so it '
      'waits at most one timeout behind the stuck call', (tester) async {
    final native = _Native()..answerFor = (_) => false;
    final p = _make(native, stored: '-1')..load(); // fails: out of step
    await tester.pump();
    native.answerFor = (_) => null; // every call hangs from now on
    unawaited(p.tick()); // the retry: in flight, stuck
    await tester.pump();
    unawaited(p.tick()); // another retry: waits behind it
    await tester.pump();
    native.received.clear();
    native.answerFor = (until) => until == 0 ? true : null;
    bool? resumed;
    unawaited(p.resume().then((v) => resumed = v));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(native.received.first, 0, reason: 'the resume is sent first');
    expect(resumed, isTrue, reason: 'one timeout after the stuck call');
    expect(p.isPaused, isFalse);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('ticks while a call is stuck queue at most one background '
      'send', (tester) async {
    final native = _Native()..answerFor = (_) => false;
    final p = _make(native, stored: '-1')..load();
    await tester.pump();
    native.answerFor = (_) => null;
    for (var i = 0; i < 10; i++) {
      unawaited(p.tick());
      await tester.pump();
    }
    native.received.clear();
    native.answerFor = (_) => true;
    await tester.pump(const Duration(seconds: 3));
    expect(native.received, [-1], reason: 'one waiting send, not nine');
  });

  testWidgets('once native answers again the next pause works', (tester) async {
    final native = _Native()..answerFor = (_) => null;
    final p = _make(native)..load();
    bool? first;
    unawaited(p.pause(PauseLength.untilResumed).then((v) => first = v));
    await tester.pump(const Duration(seconds: 5));
    expect(first, isFalse);
    native.answerFor = (_) => true;
    bool? second;
    unawaited(p.pause(PauseLength.untilResumed).then((v) => second = v));
    await tester.pump();
    expect(second, isTrue);
    expect(native.received.last, -1);
    expect(p.error, isNull);
  });
}
