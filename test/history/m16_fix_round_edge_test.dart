// M1.6 tester re-check of the fix round: O5 (a pause error stays until the
// user's next pause or resume), O6 (a clock-back cut announces nothing), O2
// (one retry of setCaptureIgnored, then a code-only log).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/history/ui/history_host.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/theme/tokens.dart';

import '../support/fakes.dart';

const _min = 60 * 1000;

class _Src extends FakeClipboardSource {
  _Src(this.answers);
  final List<Object> answers; // true, false or 'throw'
  var ignoredCalls = 0;
  final sentLists = <List<String>>[];

  @override
  Future<bool> setCaptureIgnored(List<String> appIds) async {
    final a = answers.length > ignoredCalls ? answers[ignoredCalls] : true;
    ignoredCalls++;
    sentLists.add(List.of(appIds));
    if (a == 'throw') throw StateError('channel');
    return a as bool;
  }
}

void main() {
  group('O2: setCaptureIgnored retried once, then a code', () {
    Future<(HistoryService, _Src, FakeLog)> make(List<Object> answers) async {
      final src = _Src(answers);
      final log = FakeLog();
      final h = HistoryService(
        store: MemoryHistoryStore(),
        source: src,
        log: log,
      );
      addTearDown(h.dispose);
      return (h, src, log);
    }

    test('first fails, second works: two calls, nothing logged', () async {
      final (h, src, log) = await make([false, true]);
      expect(await h.setCaptureIgnored(['a']), isTrue);
      expect(src.ignoredCalls, 2);
      expect(log.codes, isEmpty);
    });

    test('both fail (false or throw): exactly two calls, one code, no '
        'detail, no app id', () async {
      for (final answers in [
        [false, false],
        ['throw', 'throw'],
        [false, 'throw'],
      ]) {
        final (h, src, log) = await make(answers);
        expect(await h.setCaptureIgnored(['com.secret.vault']), isFalse);
        expect(src.ignoredCalls, 2, reason: '$answers');
        expect(log.codes, [LogCode.captureIgnoredSendFailed]);
        expect(log.details, [null]);
        expect(src.sentLists, [
          ['com.secret.vault'],
          ['com.secret.vault'],
        ], reason: 'the same list is retried, nothing else');
      }
    });

    test('first works: one call only', () async {
      final (h, src, log) = await make([true]);
      expect(await h.setCaptureIgnored(['a']), isTrue);
      expect(src.ignoredCalls, 1);
      expect(log.codes, isEmpty);
    });
  });

  group('O5: the error stays until the user acts', () {
    late int now;
    late bool nativeOk;
    late PauseService p;

    setUp(() {
      now = 1_762_790_400_000;
      nativeOk = true;
      p = PauseService(
        setNativePause: (_) async => nativeOk,
        readSetting: (_) => null,
        writeSetting: (_, _) => true,
        log: FakeLog(),
        persists: true,
        clock: () => now,
      )..load();
      addTearDown(p.dispose);
    });

    test('a tick retry that works leaves the apply error in place, over '
        'many ticks', () async {
      await pumpEventQueue();
      nativeOk = false;
      await p.pause(PauseLength.hour);
      expect(p.error, PauseError.apply);
      nativeOk = true;
      for (var i = 0; i < 4; i++) {
        await p.tick();
      }
      expect(p.error, PauseError.apply);
      expect(p.isPaused, isFalse, reason: 'the user pause never applied');
    });

    test('the next user pause clears it; so does a resume', () async {
      await pumpEventQueue();
      nativeOk = false;
      await p.pause(PauseLength.hour);
      nativeOk = true;
      await p.tick();
      await p.pause(PauseLength.quarterHour);
      expect(p.error, isNull);

      nativeOk = false;
      await p.resume();
      expect(p.error, PauseError.resume);
      nativeOk = true;
      await p.tick();
      expect(p.error, PauseError.resume);
      await p.resume();
      expect(p.error, isNull);
    });

    test('a failed second try keeps the newest error, not both', () async {
      await pumpEventQueue();
      nativeOk = false;
      await p.pause(PauseLength.hour);
      await p.resume();
      expect(p.error, PauseError.resume);
    });
  });

  group('O6: announcements only for real changes', () {
    testWidgets('a clock-back cut of the end time announces nothing, a '
        'timed end announces once', (tester) async {
      final handle = tester.ensureSemantics();
      var now = DateTime(2026, 11, 10, 14, 15).millisecondsSinceEpoch;
      final service = HistoryService(
        store: MemoryHistoryStore(),
        source: FakeClipboardSource(),
        log: FakeLog(),
        clock: () => now,
      )..start();
      addTearDown(service.dispose);
      tester.view.physicalSize = const Size(800, 632);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: KusungaTokens.themeData(Brightness.light),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(disableAnimations: true, alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: HistoryHost(history: Future.value(service), initial: service),
        ),
      );
      await tester.pump();
      await service.pause.pause(PauseLength.hour);
      await tester.pump();
      expect(
        find.bySemanticsLabel('History paused until 15:15'),
        findsOneWidget,
      );
      now -= 120 * _min; // clock set back: the end is cut
      await service.pause.tick();
      await tester.pump();
      expect(service.pause.pausedUntil, now + 60 * _min);
      expect(
        find.bySemanticsLabel('History paused until 15:15'),
        findsOneWidget,
        reason: 'still only the original announcement',
      );
      expect(find.bySemanticsLabel('History paused until 13:15'), findsNothing);
      expect(find.bySemanticsLabel('History resumed'), findsNothing);
      now += 61 * _min;
      await service.pause.tick();
      await tester.pump();
      expect(find.bySemanticsLabel('History resumed'), findsOneWidget);
      handle.dispose();
    });
  });
}
