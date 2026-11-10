// M1.6 tester: edge cases of the pause clock and its failure plan
// (docs/design/sensitive-content.md "Pause clock", "Failure plan").
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;

class _H {
  _H({this.persists = true, String? stored}) {
    if (stored != null) settings[historyPausedSetting] = stored;
  }

  final bool persists;
  var now = 1_762_790_400_000;
  final settings = <String, String>{};
  final sent = <int>[];
  final log = FakeLog();
  var nativeOk = true;
  var failNextWrites = 0;

  late final service = PauseService(
    setNativePause: (until) async {
      if (!nativeOk) return false;
      sent.add(until);
      return true;
    },
    readSetting: (k) => settings[k],
    writeSetting: (k, v) {
      if (failNextWrites > 0) {
        failNextWrites--;
        return false;
      }
      settings[k] = v;
      return true;
    },
    log: log,
    persists: persists,
    clock: () => now,
  );
}

void main() {
  group('clock edges at launch', () {
    test(
      'until exactly now: the pause is over, 0 is stored and sent',
      () async {
        final h = _H();
        h.settings[historyPausedSetting] = '${h.now}';
        h.service.load();
        await pumpEventQueue();
        expect(h.service.isPaused, isFalse);
        expect(h.settings[historyPausedSetting], '0');
        expect(h.sent, [0]);
        // Not a timer end: nothing is logged at load.
        expect(h.log.codes, isEmpty);
      },
    );

    test('until one ms ahead: still paused, sent unchanged', () async {
      final h = _H();
      h.settings[historyPausedSetting] = '${h.now + 1}';
      h.service.load();
      await pumpEventQueue();
      expect(h.service.isPaused, isTrue);
      expect(h.sent, [h.now + 1]);
    });

    test('exactly now + 60 min is kept; one ms more is cut', () async {
      final keep = _H();
      keep.settings[historyPausedSetting] = '${keep.now + 60 * _min}';
      keep.service.load();
      await pumpEventQueue();
      expect(keep.service.pausedUntil, keep.now + 60 * _min);

      final cut = _H();
      cut.settings[historyPausedSetting] = '${cut.now + 60 * _min + 1}';
      cut.service.load();
      await pumpEventQueue();
      expect(cut.service.pausedUntil, cut.now + 60 * _min);
      expect(cut.sent, [cut.now + 60 * _min]);
    });

    test('a tampered huge value (int64 max) is cut, not trusted', () async {
      final h = _H(stored: '9223372036854775807');
      h.service.load();
      await pumpEventQueue();
      expect(h.service.pausedUntil, h.now + 60 * _min);
      expect(h.sent.single, h.now + 60 * _min);
    });

    test('values that are not plain integers mean not paused', () {
      for (final bad in ['99999999999999999999', '0x1', '1e9', '1.5', '--1']) {
        final h = _H(stored: bad);
        h.service.load();
        expect(h.service.isPaused, isFalse, reason: bad);
        expect(h.service.untilResumed, isFalse, reason: bad);
      }
    });

    test('-1 stays -1 across a restart, whatever the clock does', () async {
      final h = _H(stored: '-1');
      h.service.load();
      h.now += 1000 * 60 * 60 * 24 * 400;
      await h.service.tick();
      expect(h.service.untilResumed, isTrue);
      expect(h.settings[historyPausedSetting], '-1');
      h.now -= 1000 * 60 * 60 * 24 * 800;
      await h.service.tick();
      expect(h.service.untilResumed, isTrue);
    });

    test('a stored 0 sends 0 and logs nothing', () async {
      final h = _H(stored: '0');
      h.service.load();
      await pumpEventQueue();
      expect(h.sent, [0]);
      expect(h.log.codes, isEmpty);
    });
  });

  group('clock moves while running', () {
    test(
      'clock moved forward past the end: the tick ends it (timer, 1)',
      () async {
        final h = _H();
        h.service.load();
        await h.service.pause(PauseLength.quarterHour);
        h.now += 3 * 60 * _min; // slept for three hours
        await h.service.tick();
        expect(h.service.isPaused, isFalse);
        expect(h.settings[historyPausedSetting], '0');
        expect(h.sent.last, 0);
        expect(h.log.codes.last, LogCode.captureResumed);
        expect(h.log.details.last, 1);
      },
    );

    test(
      'clock moved back by 2 hours: cut to now + 60 min, logged nothing',
      () async {
        final h = _H();
        h.service.load();
        await h.service.pause(PauseLength.hour);
        h.now -= 120 * _min;
        await h.service.tick();
        expect(h.service.pausedUntil, h.now + 60 * _min);
        expect(h.settings[historyPausedSetting], '${h.now + 60 * _min}');
        expect(h.sent.last, h.now + 60 * _min);
        expect(h.log.codes.where((c) => c == LogCode.captureResumed), isEmpty);
      },
    );

    test('the end time is exact: paused at end - 1 ms, over at end', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      final end = h.service.pausedUntil;
      h.now = end - 1;
      expect(h.service.isPaused, isTrue);
      h.now = end;
      // Before the tick Dart already says "not paused" (as native does).
      expect(h.service.isPaused, isFalse);
      expect(h.service.endsAt, isNull);
    });

    test('the timer end is logged once, however many ticks follow', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.now += 16 * _min;
      await h.service.tick();
      await h.service.tick();
      await h.service.tick();
      expect(
        h.log.codes.where((c) => c == LogCode.captureResumed),
        hasLength(1),
      );
    });

    test('a user Resume logs 0 and never a timer end', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.hour);
      await h.service.resume();
      h.now += 2 * 60 * _min;
      await h.service.tick();
      expect(h.log.codes, [LogCode.capturePaused, LogCode.captureResumed]);
      expect(h.log.details, [60, 0]);
    });

    test('log details carry only 15, 60 or -1', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      await h.service.pause(PauseLength.hour);
      await h.service.pause(PauseLength.untilResumed);
      expect(h.log.details, [15, 60, -1]);
    });
  });

  group('failure plan', () {
    test('memory-only: the pause applies, willLast is false', () async {
      final h = _H(persists: false);
      h.service.load();
      expect(await h.service.pause(PauseLength.hour), isTrue);
      expect(h.service.isPaused, isTrue);
      expect(h.service.willLast, isFalse);
    });

    test('a failed save keeps the pause for the session', () async {
      final h = _H();
      h.service.load();
      h.failNextWrites = 1;
      expect(await h.service.pause(PauseLength.untilResumed), isTrue);
      expect(h.service.isPaused, isTrue);
      expect(h.service.willLast, isFalse);
    });

    test('a later successful save clears "won\'t last"', () async {
      // A transient write failure must not leave the note on for the rest of
      // the session once the setting is saved again.
      final h = _H();
      h.service.load();
      h.failNextWrites = 1;
      await h.service.pause(PauseLength.untilResumed);
      expect(h.service.willLast, isFalse);
      await h.service.resume();
      await h.service.pause(PauseLength.untilResumed);
      expect(h.settings[historyPausedSetting], '-1');
      expect(h.service.willLast, isTrue);
    });

    test(
      'retry once: the second failed tick does not call native again',
      () async {
        final h = _H();
        h.service.load();
        await pumpEventQueue();
        h.nativeOk = false;
        expect(await h.service.pause(PauseLength.hour), isFalse);
        expect(h.service.error, PauseError.apply);
        var calls = 0;
        final svc = PauseService(
          setNativePause: (_) async {
            calls++;
            return false;
          },
          readSetting: (_) => null,
          writeSetting: (_, _) => true,
          log: FakeLog(),
          persists: true,
          clock: () => h.now,
        );
        await svc.pause(PauseLength.hour); // fails, calls = 1
        await svc.tick(); // the one retry
        await svc.tick();
        await svc.tick();
        expect(calls, 2);
        expect(svc.error, PauseError.apply);
      },
    );

    test(
      'a failed pause changes nothing: not paused, not stored, not logged',
      () async {
        final h = _H();
        h.service.load();
        h.nativeOk = false;
        await h.service.pause(PauseLength.untilResumed);
        expect(h.service.isPaused, isFalse);
        expect(h.settings[historyPausedSetting], isNull);
        expect(h.log.codes, isEmpty);
      },
    );

    test('a native call that throws counts as a failure', () async {
      final svc = PauseService(
        setNativePause: (_) async => throw StateError('channel gone'),
        readSetting: (_) => null,
        writeSetting: (_, _) => true,
        log: FakeLog(),
        persists: true,
        clock: () => 1_762_790_400_000,
      );
      expect(await svc.pause(PauseLength.hour), isFalse);
      expect(svc.error, PauseError.apply);
      expect(svc.isPaused, isFalse);
    });

    test(
      'a failed resume keeps the pause, the setting and the log clean',
      () async {
        final h = _H();
        h.service.load();
        await h.service.pause(PauseLength.untilResumed);
        h.nativeOk = false;
        expect(await h.service.resume(), isFalse);
        expect(h.service.error, PauseError.resume);
        expect(h.service.untilResumed, isTrue);
        expect(h.settings[historyPausedSetting], '-1');
        expect(h.log.codes, [LogCode.capturePaused]);
      },
    );

    test('a later successful call clears the error', () async {
      final h = _H();
      h.service.load();
      h.nativeOk = false;
      await h.service.pause(PauseLength.hour);
      h.nativeOk = true;
      await h.service.pause(PauseLength.hour);
      expect(h.service.error, isNull);
    });

    test('a timed pause that ends while native is unreachable is still not '
        'paused in Dart, and is retried on a later tick', () async {
      final h = _H();
      h.service.load();
      await h.service.pause(PauseLength.quarterHour);
      h.nativeOk = false;
      h.now += 20 * _min;
      await h.service.tick();
      expect(h.service.isPaused, isFalse);
      h.nativeOk = true;
      h.sent.clear();
      await h.service.tick();
      expect(h.sent, [0], reason: 'native must be told 0 on the retry');
    });

    test(
      'overlapping pause and resume calls end in the last one asked',
      () async {
        final h = _H();
        h.service.load();
        final a = h.service.pause(PauseLength.hour);
        final b = h.service.resume();
        await Future.wait([a, b]);
        expect(h.service.isPaused, isFalse);
        expect(h.sent.last, 0);
        expect(h.settings[historyPausedSetting], '0');
      },
    );

    test('dispose stops ticks and notifications', () async {
      final h = _H();
      h.service.load();
      var n = 0;
      h.service.addListener(() => n++);
      h.service.dispose();
      await h.service.tick();
      expect(n, 0);
    });
  });

  group('formatPauseEnd', () {
    test('12-hour format at midnight and noon', () {
      final day = DateTime(2026, 11, 10, 9);
      expect(
        formatPauseEnd(DateTime(2026, 11, 10, 0, 5), day, use24Hour: false),
        '12:05 AM',
      );
      expect(
        formatPauseEnd(DateTime(2026, 11, 10, 12, 5), day, use24Hour: false),
        '12:05 PM',
      );
      expect(
        formatPauseEnd(DateTime(2026, 11, 10, 13, 0), day, use24Hour: false),
        '1:00 PM',
      );
    });

    test('across midnight: tomorrow, in both formats', () {
      final now = DateTime(2026, 11, 10, 23, 55);
      final end = DateTime(2026, 11, 11, 0, 10);
      expect(formatPauseEnd(end, now, use24Hour: true), 'tomorrow 00:10');
      expect(formatPauseEnd(end, now, use24Hour: false), 'tomorrow 12:10 AM');
    });

    test('across a month and a year end', () {
      expect(
        formatPauseEnd(
          DateTime(2027, 1, 1, 0, 10),
          DateTime(2026, 12, 31, 23, 55),
          use24Hour: true,
        ),
        'tomorrow 00:10',
      );
    });
  });
}
