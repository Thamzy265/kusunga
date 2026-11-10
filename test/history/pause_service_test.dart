// M1.6 "Pause history" (docs/design/sensitive-content.md, "Pause clock" and
// "Failure plan"): the setting, the 60-minute cap when the clock is set
// back, the 15 s tick, and the native call.
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;

class _Harness {
  _Harness({this.persists = true, String? stored}) {
    if (stored != null) settings[historyPausedSetting] = stored;
  }

  final bool persists;
  var now = 1_762_790_400_000; // 2025-11-10 16:00 UTC
  final settings = <String, String>{};
  final sent = <int>[];
  final log = FakeLog();
  var nativeOk = true;
  var writeOk = true;

  late final service = PauseService(
    setNativePause: (until) async {
      if (!nativeOk) return false;
      sent.add(until);
      return true;
    },
    readSetting: (k) => settings[k],
    writeSetting: (k, v) {
      if (!writeOk) return false;
      settings[k] = v;
      return true;
    },
    log: log,
    persists: persists,
    clock: () => now,
  );
}

void main() {
  test('the setting key is history_paused_until', () {
    expect(historyPausedSetting, 'history_paused_until');
  });

  group('load (before the watcher starts)', () {
    test('no setting: not paused, and native is told 0', () async {
      final h = _Harness();
      h.service.load();
      await pumpEventQueue();
      expect(h.service.isPaused, isFalse);
      expect(h.service.pausedUntil, 0);
      expect(h.sent, [0]);
    });

    test('until resumed survives a restart (D3 A)', () async {
      final h = _Harness(stored: '-1');
      h.service.load();
      await pumpEventQueue();
      expect(h.service.isPaused, isTrue);
      expect(h.service.untilResumed, isTrue);
      expect(h.sent, [-1]);
    });

    test('a timed pause continues to its end time', () async {
      final h = _Harness();
      h.settings[historyPausedSetting] = '${h.now + 10 * _min}';
      h.service.load();
      await pumpEventQueue();
      expect(h.service.isPaused, isTrue);
      expect(h.service.pausedUntil, h.now + 10 * _min);
      expect(h.sent, [h.now + 10 * _min]);
    });

    test(
      'a timed pause that ended while Kusunga was closed is cleared',
      () async {
        final h = _Harness();
        h.settings[historyPausedSetting] = '${h.now - 1}';
        h.service.load();
        await pumpEventQueue();
        expect(h.service.isPaused, isFalse);
        expect(h.settings[historyPausedSetting], '0');
        expect(h.sent, [0]);
      },
    );

    test(
      'an end more than 60 min away (clock set back) is cut to now + 60',
      () async {
        final h = _Harness();
        h.settings[historyPausedSetting] = '${h.now + 5 * 60 * _min}';
        h.service.load();
        await pumpEventQueue();
        expect(h.service.pausedUntil, h.now + 60 * _min);
        expect(h.settings[historyPausedSetting], '${h.now + 60 * _min}');
        expect(h.sent, [h.now + 60 * _min]);
      },
    );

    test(
      'a value that is not a number, or below -1, means not paused',
      () async {
        for (final bad in ['x', '', '-5', '1.5']) {
          final h = _Harness(stored: bad);
          h.service.load();
          expect(h.service.isPaused, isFalse, reason: bad);
          expect(h.service.pausedUntil, 0, reason: bad);
        }
      },
    );

    test('the native call is started synchronously, before load returns', () {
      final h = _Harness(stored: '-1');
      var calls = 0;
      final service = PauseService(
        setNativePause: (until) {
          calls++;
          return Future.value(true);
        },
        readSetting: (k) => h.settings[k],
        writeSetting: (_, _) => true,
        log: h.log,
        persists: true,
      );
      service.load();
      expect(calls, 1);
    });
  });

  group('pause and resume', () {
    test('for 15 minutes, 1 hour and until resumed', () async {
      final h = _Harness();
      h.service.load();
      expect(await h.service.pause(PauseLength.quarterHour), isTrue);
      expect(h.service.pausedUntil, h.now + 15 * _min);
      expect(h.settings[historyPausedSetting], '${h.now + 15 * _min}');
      expect(await h.service.pause(PauseLength.hour), isTrue);
      expect(h.service.pausedUntil, h.now + 60 * _min);
      expect(await h.service.pause(PauseLength.untilResumed), isTrue);
      expect(h.service.pausedUntil, -1);
      expect(h.settings[historyPausedSetting], '-1');
      expect(h.sent, [0, h.now + 15 * _min, h.now + 60 * _min, -1]);
    });

    test('logs capturePaused with the length only, and captureResumed '
        '(0 user)', () async {
      final h = _Harness();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      await h.service.pause(PauseLength.hour);
      await h.service.pause(PauseLength.untilResumed);
      await h.service.resume();
      expect(h.log.codes, [
        LogCode.capturePaused,
        LogCode.capturePaused,
        LogCode.capturePaused,
        LogCode.captureResumed,
      ]);
      expect(h.log.details, [15, 60, -1, 0]);
    });

    test('resume writes 0 and tells native', () async {
      final h = _Harness(stored: '-1');
      h.service.load();
      expect(await h.service.resume(), isTrue);
      expect(h.service.isPaused, isFalse);
      expect(h.settings[historyPausedSetting], '0');
      expect(h.sent.last, 0);
    });

    test('listeners hear each change', () async {
      final h = _Harness();
      h.service.load();
      var heard = 0;
      h.service.addListener(() => heard++);
      await h.service.pause(PauseLength.hour);
      await h.service.resume();
      expect(heard, greaterThanOrEqualTo(2));
    });
  });

  group('failure plan', () {
    test('native call fails on pause: state kept, apply error, retried once '
        'on the next tick', () async {
      final h = _Harness();
      h.service.load();
      await pumpEventQueue();
      h.nativeOk = false;
      expect(await h.service.pause(PauseLength.hour), isFalse);
      expect(h.service.isPaused, isFalse);
      expect(h.service.error, PauseError.apply);
      expect(h.settings[historyPausedSetting], isNull);
      expect(h.log.codes, isNot(contains(LogCode.capturePaused)));
      // Next tick: one retry of Dart's own state; still failing.
      await h.service.tick();
      expect(h.service.error, PauseError.apply);
      // Only once: later ticks don't retry again.
      h.nativeOk = true;
      h.sent.clear();
      await h.service.tick();
      expect(h.sent, isEmpty);
    });

    test('a retry that works clears the error', () async {
      final h = _Harness();
      h.service.load();
      await pumpEventQueue();
      h.nativeOk = false;
      await h.service.pause(PauseLength.hour);
      h.nativeOk = true;
      h.sent.clear();
      await h.service.tick();
      expect(h.sent, [0]);
      expect(h.service.error, isNull);
    });

    test('native call fails on resume: stays paused, resume error', () async {
      final h = _Harness(stored: '-1');
      h.service.load();
      await pumpEventQueue();
      h.nativeOk = false;
      expect(await h.service.resume(), isFalse);
      expect(h.service.isPaused, isTrue);
      expect(h.service.error, PauseError.resume);
      // A later successful action clears it.
      h.nativeOk = true;
      expect(await h.service.resume(), isTrue);
      expect(h.service.error, isNull);
    });

    test('the setting can\'t be written: the pause applies for the session '
        'and says it won\'t last', () async {
      final h = _Harness();
      h.service.load();
      expect(h.service.willLast, isTrue);
      h.writeOk = false;
      expect(await h.service.pause(PauseLength.untilResumed), isTrue);
      expect(h.service.isPaused, isTrue);
      expect(h.service.willLast, isFalse);
    });

    test('memory-only mode: the pause applies, and never lasts', () async {
      final h = _Harness(persists: false);
      h.service.load();
      expect(h.service.willLast, isFalse);
      expect(await h.service.pause(PauseLength.quarterHour), isTrue);
      expect(h.service.isPaused, isTrue);
    });
  });

  group('the clock', () {
    test(
      'a tick after the end time resumes (timer), writes 0, tells native',
      () async {
        final h = _Harness();
        h.service.load();
        await h.service.pause(PauseLength.quarterHour);
        h.now += 15 * _min;
        h.log.codes.clear();
        h.log.details.clear();
        await h.service.tick();
        expect(h.service.isPaused, isFalse);
        expect(h.settings[historyPausedSetting], '0');
        expect(h.sent.last, 0);
        expect(h.log.codes, [LogCode.captureResumed]);
        expect(h.log.details, [1]);
      },
    );

    test('isPaused follows the wall clock even before a tick', () async {
      final h = _Harness();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.now += 15 * _min;
      expect(h.service.isPaused, isFalse);
    });

    test('a tick cuts an end more than 60 min away (clock set back)', () async {
      final h = _Harness();
      h.service.load();
      await h.service.pause(PauseLength.hour);
      h.now -= 3 * 60 * _min; // the clock went back 3 hours
      await h.service.tick();
      expect(h.service.pausedUntil, h.now + 60 * _min);
      expect(h.settings[historyPausedSetting], '${h.now + 60 * _min}');
      expect(h.sent.last, h.now + 60 * _min);
    });

    test('until resumed is never ended by a tick', () async {
      final h = _Harness();
      h.service.load();
      await h.service.pause(PauseLength.untilResumed);
      h.now += 1000 * 60 * _min;
      await h.service.tick();
      expect(h.service.isPaused, isTrue);
    });

    testWidgets('startTicking ticks every 15 s until disposed', (tester) async {
      final h = _Harness();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.service.startTicking(listenToLifecycle: false);
      h.now += 15 * _min;
      await tester.pump(const Duration(seconds: 14));
      expect(h.service.pausedUntil, isNot(0));
      await tester.pump(const Duration(seconds: 1));
      expect(h.service.pausedUntil, 0);
      h.service.dispose();
      // No timer left behind (testWidgets fails on a pending timer).
    });
  });

  group('formatPauseEnd', () {
    final now = DateTime(2026, 11, 10, 14, 0);

    test('today: the time only, in the system 12/24-hour format', () {
      expect(
        formatPauseEnd(DateTime(2026, 11, 10, 14, 30), now, use24Hour: true),
        '14:30',
      );
      expect(
        formatPauseEnd(DateTime(2026, 11, 10, 14, 30), now, use24Hour: false),
        '2:30 PM',
      );
      expect(
        formatPauseEnd(DateTime(2026, 11, 10, 0, 5), now, use24Hour: false),
        '12:05 AM',
      );
    });

    test('not today: "tomorrow" before the time', () {
      expect(
        formatPauseEnd(
          DateTime(2026, 11, 11, 0, 10),
          DateTime(2026, 11, 10, 23, 30),
          use24Hour: true,
        ),
        'tomorrow 00:10',
      );
    });
  });
}
