// M1.7 tester: auto-delete edge cases on the service level
// (docs/design/settings-and-expiry.md "Auto-delete", "Failure plan"): the
// cutoff to the millisecond, the clock set back and forward, a re-copy,
// snippets (R2), and the clean-up warning. The clock is injected.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/expiry_service.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/snippets/snippet.dart';

import '../support/fakes.dart';

const day = Duration.millisecondsPerDay;

void main() {
  late FakeClipboardSource source;
  late FlakyStore store;
  late FakeLog log;
  late HistoryService service;
  var now = 0;

  HistoryService build() => HistoryService(
    store: store,
    source: source,
    log: log,
    clock: () => now,
    writeClipboard: (_) async {},
  )..start();

  setUp(() {
    now = 400 * day;
    source = FakeClipboardSource();
    store = FlakyStore(MemoryHistoryStore());
    log = FakeLog();
  });
  tearDown(() => service.dispose());

  List<String> texts() => service.items.map((i) => i.preview).toList();

  group(
    'the cutoff to the millisecond (R1: read filter and clean-up agree)',
    () {
      for (final days in [1, 7, 30]) {
        test('$days day(s): exactly that old is shown and kept; 1 ms older is '
            'hidden and then deleted', () {
          store.inner.writeSetting(historyExpirySetting, '$days');
          store.inner.insertOrBump('gone', ClipKind.text, now - days * day - 1);
          store.inner.insertOrBump('edge', ClipKind.text, now - days * day);
          service = build(); // the clean-up already ran at launch
          expect(texts(), ['edge']);
          expect(store.inner.count, 1, reason: 'the clean-up used the same >=');
          now += 1; // the edge item is now 1 ms past it
          service.expiry.cleanUp();
          expect(texts(), isEmpty);
          expect(store.inner.count, 0);
        });
      }

      test(
        'the filter hides an item the moment it passes, before any clean-up',
        () {
          store.inner.writeSetting(historyExpirySetting, '1');
          store.inner.insertOrBump('a', ClipKind.text, now);
          service = build();
          now += day; // exactly 1 day old: still shown
          service.expiry.cleanUp();
          expect(texts(), ['a']);
          now += 1;
          // No clean-up has run: only a refresh (any list change) happens.
          source.copy('b');
          expect(texts(), ['b']);
          expect(store.inner.count, 2, reason: 'a is hidden, not yet deleted');
        },
      );
    },
  );

  group('the clock', () {
    test('set back: nothing is lost and nothing extra is shown; set forward '
        'again: the same items go', () {
      store.inner.writeSetting(historyExpirySetting, '7');
      store.inner.insertOrBump('a', ClipKind.text, now - 6 * day);
      service = build();
      now -= 400 * day; // back to near epoch: a is "from the future"
      service.expiry.cleanUp();
      expect(texts(), ['a']);
      now += 400 * day + 2 * day; // forward: a is 8 days old
      service.expiry.cleanUp();
      expect(texts(), isEmpty);
      expect(store.inner.count, 0);
    });

    test('a negative or zero clock does not crash and deletes nothing', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      store.inner.insertOrBump('a', ClipKind.text, 5);
      now = 0;
      service = build();
      expect(texts(), ['a']);
      now = -5 * day;
      service.expiry.cleanUp();
      expect(texts(), ['a']);
    });

    test('expiryCutoff: Never is null, otherwise now minus whole days', () {
      expect(expiryCutoff(0, 5), isNull);
      expect(expiryCutoff(1, 2 * day), day);
      expect(expiryCutoff(30, 30 * day), 0);
    });
  });

  group('a re-copy', () {
    test(
      'keeps the item: the clean-up never removes what was copied again',
      () {
        store.inner.writeSetting(historyExpirySetting, '1');
        store.inner.insertOrBump('keepme', ClipKind.text, now - 5 * day);
        service = build(); // expired and removed at launch
        expect(texts(), isEmpty);

        store.inner.insertOrBump('keepme', ClipKind.text, now - 2 * day);
        now -= 0;
        source.copy('keepme'); // copied just now
        service.expiry.cleanUp();
        now += day - 1;
        service.expiry.cleanUp();
        expect(texts(), ['keepme']);
      },
    );

    test('an item that expired but is not cleaned up yet, copied again, is '
        'shown once and not removed', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      source.copy('twice');
      now += 2 * day; // expired; no clean-up ran
      source.copy('twice');
      expect(texts(), ['twice']);
      expect(store.inner.count, 1);
      service.expiry.cleanUp();
      expect(texts(), ['twice']);
    });
  });

  group('snippets (R2)', () {
    test('a snippet with the same text as an expired item is not removed, '
        'and its text still pastes', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.inner.insertOrBump('+44 7700 900123', ClipKind.text, now - 9 * day);
      service = build();
      service.snippets.save(
        name: 'Phone',
        content: '+44 7700 900123',
        type: SnippetType.other,
      );
      now += 400 * day;
      service.expiry.cleanUp();
      expect(texts(), isEmpty);
      expect(service.snippets.items.map((s) => s.name), ['Phone']);
      expect(
        service.snippets.textOf(service.snippets.items.single.id),
        '+44 7700 900123',
      );
    });
  });

  group('the clean-up warning', () {
    void fail3() {
      store.inner.writeSetting(historyExpirySetting, '30');
      store.failWrites = true;
      service = build();
      service.expiry.cleanUp();
      service.expiry.cleanUp();
      expect(service.banners, contains(HistoryBanner.expiryFailed));
    }

    test('choosing Never stops the warning: nothing is being cleaned up', () {
      fail3();
      store.failWrites = false;
      expect(service.expiry.setDays(0), 0);
      expect(service.expiry.failing, isFalse);
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
    });

    test('a save that fails leaves the warning as it was', () {
      fail3();
      expect(service.expiry.setDays(1), isNull);
      expect(service.banners, contains(HistoryBanner.expiryFailed));
    });

    test('2 failures, a success, then 2 failures: no warning; the 3rd in a '
        'row shows it', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      store.failWrites = true;
      service.expiry.cleanUp();
      service.expiry.cleanUp();
      store.failWrites = false;
      service.expiry.cleanUp();
      store.failWrites = true;
      service.expiry.cleanUp();
      service.expiry.cleanUp();
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
      service.expiry.cleanUp();
      expect(service.banners, contains(HistoryBanner.expiryFailed));
    });

    test('each failed run logs historyExpiryFailed once, with no number', () {
      fail3();
      final failed = [
        for (var i = 0; i < log.codes.length; i++)
          if (log.codes[i] == LogCode.historyExpiryFailed) log.details[i],
      ];
      expect(failed, [null, null, null]);
    });
  });

  group('the dialog count and what is deleted', () {
    test('the count in the dialog equals what Delete removes, also when some '
        'expired items are still waiting for the clean-up', () {
      store.inner.writeSetting(historyExpirySetting, '7');
      service = build();
      store.inner.insertOrBump('hidden1', ClipKind.text, now - 9 * day);
      store.inner.insertOrBump('hidden2', ClipKind.text, now - 8 * day);
      store.inner.insertOrBump('dialog', ClipKind.text, now - 3 * day);
      store.inner.insertOrBump('fresh', ClipKind.text, now);
      final counted = service.expiry.countRemovedBy(1);
      final removed = service.expiry.setDays(1);
      expect(removed, counted);
    });
  });

  group('the minute check on a wall clock that jumps', () {
    const minute = Duration.millisecondsPerMinute;

    testWidgets('a jump forward (a long sleep) cleans up at the next check, '
        'not 15 minutes later', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.inner.insertOrBump('a', ClipKind.text, now - 1000);
      service = build();
      service.expiry.startTicking(listenToLifecycle: false);
      now += 5 * day; // slept for 5 days; the timer ran only once
      await tester.pump(const Duration(minutes: 1));
      expect(store.inner.count, 0);
      expect(texts(), isEmpty);
      service.dispose();
    });

    testWidgets('3 failing runs, 15 minutes apart, show the warning; a good '
        'one clears it', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build(); // run 1 (ok: nothing to delete)
      service.expiry.startTicking(listenToLifecycle: false);
      store.failWrites = true;
      Future<void> fifteen() async {
        for (var i = 0; i < 15; i++) {
          now += minute;
          await tester.pump(const Duration(minutes: 1));
        }
      }

      await fifteen();
      await fifteen();
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
      await fifteen();
      expect(service.banners, contains(HistoryBanner.expiryFailed));
      store.failWrites = false;
      await fifteen();
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
      service.dispose();
    });

    testWidgets('the check still deletes while history is paused', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      await service.pause.pause(PauseLength.untilResumed);
      service.expiry.startTicking(listenToLifecycle: false);
      store.inner.insertOrBump('old', ClipKind.text, now - 2 * day);
      for (var i = 0; i < 15; i++) {
        now += minute;
        await tester.pump(const Duration(minutes: 1));
      }
      expect(store.inner.count, 0);
      service.dispose();
    });

    testWidgets('becoming active again cleans up at once', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      service.expiry.startTicking();
      store.inner.insertOrBump('old', ClipKind.text, now - 2 * day);
      final b = tester.binding;
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(store.inner.count, 1);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(store.inner.count, 0);
      service.dispose();
    });

    testWidgets('after dispose nothing runs and no timer is left', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      service.expiry.startTicking();
      service.dispose();
      store.inner.insertOrBump('old', ClipKind.text, now - 2 * day);
      now += 20 * minute;
      await tester.pump(const Duration(minutes: 30));
      expect(store.inner.count, 1);
      service.expiry.cleanUp(); // a late call is ignored
      expect(store.inner.count, 1);
    });
  });
}
