// M1.7 auto-delete (docs/design/settings-and-expiry.md, "Auto-delete" and
// "Failure plan"): the read filter, the clean-up and its clock, a shorter
// time, and the warning after 3 failed runs. The clock is injected.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/clip_item.dart';
import 'package:kusunga/history/expiry_service.dart';
import 'package:kusunga/history/history_opener.dart';
import 'package:kusunga/history/history_service.dart';
import 'package:kusunga/history/history_store.dart';
import 'package:kusunga/history/memory_history_store.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';

import '../support/fakes.dart';

const day = Duration.millisecondsPerDay;
const minute = Duration.millisecondsPerMinute;

void main() {
  late FakeClipboardSource source;
  late FlakyStore store;
  late FakeLog log;
  late HistoryService service;
  late List<String> written;
  var now = 0;

  HistoryService build({Set<HistoryNotice> notices = const {}}) =>
      HistoryService(
        store: store,
        notices: notices,
        source: source,
        log: log,
        clock: () => now,
        writeClipboard: (text) async => written.add(text),
      )..start();

  setUp(() {
    written = [];
    now = 100 * day;
    source = FakeClipboardSource();
    store = FlakyStore(MemoryHistoryStore());
    log = FakeLog();
  });
  tearDown(() => service.dispose());

  List<String> texts() => service.items.map((i) => i.preview).toList();

  // Oldest first: a store never saves an item older than its newest one.
  void seed(Map<String, int> ageInDays) {
    final byAge = ageInDays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final MapEntry(key: text, value: age) in byAge) {
      store.inner.insertOrBump(text, ClipKind.text, now - age * day);
    }
  }

  group('loading the setting', () {
    test('a valid value is used', () {
      store.inner.writeSetting(historyExpirySetting, '7');
      service = build();
      expect(service.expiry.days, 7);
      expect(log.codes, isNot(contains(LogCode.readFailed)));
    });

    for (final bad in ['2', '-1', '365', 'abc', '30.0', '07']) {
      test('"$bad" counts as Never, with a log code', () {
        store.inner.writeSetting(historyExpirySetting, bad);
        service = build();
        expect(service.expiry.days, 0);
        expect(log.codes, contains(LogCode.readFailed));
      });
    }

    test('a missing row counts as Never, with a log code', () {
      final empty = _NoSettingStore();
      store = FlakyStore(empty);
      service = build();
      expect(service.expiry.days, 0);
      expect(log.codes, contains(LogCode.readFailed));
    });

    test('a read error counts as Never, with a log code', () {
      store = FlakyStore(_ThrowingReadStore());
      service = build();
      expect(service.expiry.days, 0);
      expect(log.codes, contains(LogCode.readFailed));
    });

    // Reviewer F4: a read that throws is "unknown", not the user's Never for
    // the whole session. It is read again at each check and clean-up.
    int readFailures() =>
        log.codes.where((c) => c == LogCode.readFailed).length;

    test('a read that throws is read again at the next check; once it '
        'reads, the chosen time applies at once', () {
      final inner = _SometimesUnreadable()
        ..writeSetting(historyExpirySetting, '1');
      store = FlakyStore(inner);
      seed({'old': 2, 'new': 0});
      service = build();
      expect(service.expiry.days, 0);
      expect(texts(), ['new', 'old']);
      expect(readFailures(), 1);
      now += minute;
      service.expiry.check();
      expect(service.expiry.days, 0);
      expect(readFailures(), 1, reason: 'logged once while it keeps failing');
      inner.fail = false;
      now += minute;
      service.expiry.check();
      expect(service.expiry.days, 1);
      expect(texts(), ['new']);
      expect(store.inner.count, 1, reason: 'the clean-up ran at once');
      expect(readFailures(), 1);
    });

    test('the clean-up reads it again too', () {
      final inner = _SometimesUnreadable()
        ..writeSetting(historyExpirySetting, '7');
      store = FlakyStore(inner);
      seed({'old': 8});
      service = build();
      expect(store.inner.count, 1);
      inner.fail = false;
      service.expiry.cleanUp();
      expect(service.expiry.days, 7);
      expect(store.inner.count, 0);
    });

    test('a time chosen while it was unknown is kept; it is not read '
        'again', () {
      final inner = _SometimesUnreadable()
        ..writeSetting(historyExpirySetting, '30');
      store = FlakyStore(inner);
      service = build();
      expect(service.expiry.setDays(7), 0);
      inner
        ..fail = false
        ..writeSetting(historyExpirySetting, '30');
      now += minute;
      service.expiry.check();
      expect(service.expiry.days, 7);
    });

    test('a crafted value still means Never and is not read again', () {
      store.inner.writeSetting(historyExpirySetting, '2');
      service = build();
      expect(readFailures(), 1);
      store.inner.writeSetting(historyExpirySetting, '1');
      now += minute;
      service.expiry.check();
      service.expiry.cleanUp();
      expect(service.expiry.days, 0);
      expect(readFailures(), 1);
    });
  });

  group('read filter (R1)', () {
    test('an item older than the chosen time is never shown, even before '
        'the clean-up', () {
      store.inner.writeSetting(historyExpirySetting, '7');
      seed({'old': 8, 'edge': 7, 'new': 1});
      store.failWrites = true; // the clean-up fails
      service = build();
      expect(texts(), ['new', 'edge']);
      expect(store.inner.count, 3);
    });

    test('Never shows everything', () {
      seed({'old': 400, 'new': 1});
      service = build();
      expect(service.expiry.days, 0);
      expect(texts(), ['new', 'old']);
    });

    test('items that age out are hidden at the next refresh', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.failWrites = true;
      seed({'a': 0});
      service = build();
      expect(texts(), ['a']);
      now += day + 1;
      service.expiry.cleanUp(); // fails: nothing deleted, nothing refreshed
      source.copy('b'); // the next refresh
      expect(texts(), ['b']);
      expect(store.inner.count, 1);
    });

    // An id kept from before the item expired (a row on screen, the picker)
    // must not reach its text once the cut-off has passed it.
    test('textOf and copy give nothing for an item that expired but is not '
        'cleaned up yet; up to the cut-off they still work', () async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      source.copy('secret');
      final id = service.items.single.id;
      expect(id, isPositive);
      now += day; // exactly 1 day: still shown
      expect(service.textOf(id), 'secret');
      expect(await service.copy(id), isTrue);
      expect(written, ['secret']);
      now += 1; // expired; no clean-up has run
      expect(service.textOf(id), isNull);
      expect(await service.copy(id), isFalse);
      expect(written, ['secret']);
      expect(store.inner.count, 1, reason: 'hidden, not deleted');
    });

    test('a copy waiting to be saved honours the cut-off too', () async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      store.failWrites = true;
      source.copy('waiting');
      final id = service.items.single.id;
      expect(id, isNegative);
      now += day;
      expect(service.textOf(id), 'waiting');
      now += 1;
      expect(service.textOf(id), isNull);
      expect(await service.copy(id), isFalse);
      expect(written, isEmpty);
    });

    test('Never: textOf and copy of an old item still work', () async {
      seed({'old': 400});
      service = build();
      final id = service.items.single.id;
      expect(service.textOf(id), 'old');
      expect(await service.copy(id), isTrue);
    });
  });

  group('clean-up', () {
    test('runs at launch, after the migration, and logs the count', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'old': 31, 'older': 40, 'new': 2});
      service = build();
      expect(store.inner.count, 1);
      expect(texts(), ['new']);
      final i = log.codes.indexOf(LogCode.historyExpired);
      expect(i, greaterThanOrEqualTo(0));
      expect(log.details[i], 2);
    });

    test('nothing to delete: no log line', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'new': 2});
      service = build();
      expect(log.codes, isNot(contains(LogCode.historyExpired)));
    });

    test('Never deletes nothing', () {
      seed({'old': 1000});
      service = build();
      service.expiry.cleanUp();
      expect(store.inner.count, 1);
    });

    test('still runs while history is paused', () async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      await service.pause.pause(PauseLength.untilResumed);
      seed({'old': 2});
      service.expiry.cleanUp();
      expect(store.inner.count, 0);
    });

    test('the limit still applies too', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      store.inner.setLimit(10);
      service = build();
      for (var i = 0; i < 12; i++) {
        source.copy('item $i');
        now += 1;
      }
      expect(store.inner.count, 10);
    });

    test('a clock set forward deletes early; set back keeps items, hidden '
        'nothing extra', () {
      store.inner.writeSetting(historyExpirySetting, '7');
      seed({'a': 3});
      service = build();
      now += 5 * day; // forward: a is 8 days old now
      service.expiry.cleanUp();
      expect(store.inner.count, 0);

      seed({'b': 3});
      now -= 30 * day; // back: b looks newer than now
      service.expiry.cleanUp();
      expect(store.inner.count, 1);
      source.copy('c'); // the next refresh
      expect(texts(), ['c', 'b']);
    });

    // Reviewer F11: listeners hear from a clean-up only when something
    // changed.
    test('a run that changes nothing notifies no one; one that deletes, or '
        'whose warning comes or goes, does', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      seed({'new': 0});
      service = build();
      var heard = 0;
      service.addListener(() => heard++);
      service.expiry.addListener(() => heard++);
      service.expiry.cleanUp();
      expect(heard, 0, reason: 'nothing deleted, no warning change');
      now += day + 1;
      service.expiry.cleanUp();
      expect(heard, greaterThan(0), reason: 'an item was deleted');
      heard = 0;
      store.failWrites = true;
      service.expiry.cleanUp();
      service.expiry.cleanUp();
      expect(heard, 0, reason: '2 failures: no warning yet');
      service.expiry.cleanUp();
      expect(heard, greaterThan(0), reason: 'the warning shows');
      heard = 0;
      service.expiry.cleanUp();
      expect(heard, 0, reason: 'still failing: no change');
      store.failWrites = false;
      service.expiry.cleanUp();
      expect(heard, greaterThan(0), reason: 'the warning goes');
    });

    // Reviewer F6: a copy that could not be saved yet and has expired
    // meanwhile is never written.
    List<String> saved() => store.inner.list().map((i) => i.preview).toList();

    test('an expired copy waiting to be saved is dropped at the clean-up '
        'and never written', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      store.failWrites = true;
      source.copy('secret');
      expect(service.banners, contains(HistoryBanner.writeError));
      now += day + 1;
      store.failWrites = false;
      service.expiry.cleanUp();
      expect(texts(), isEmpty);
      expect(service.banners, isNot(contains(HistoryBanner.writeError)));
      source.copy('next');
      expect(saved(), ['next']);
    });

    test('a save between clean-ups skips an expired waiting copy', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      store.failWrites = true;
      source.copy('secret');
      source.copy('kept');
      now += day - 1;
      source.copy('newer'); // still waiting: writes fail
      now += 2; // 'secret' and 'kept' have expired, 'newer' has not
      store.failWrites = false;
      source.copy('last');
      expect(saved(), ['last', 'newer']);
    });

    test('quitting does not write an expired waiting copy', () async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      store.failWrites = true;
      source.copy('secret');
      now += day + 1;
      store.failWrites = false;
      await service.close();
      expect(saved(), isEmpty);
    });

    test('a failed run keeps items hidden, logs, and retries next run', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      seed({'old': 2, 'new': 0});
      store.failWrites = true;
      service = build();
      expect(texts(), ['new']);
      expect(log.codes, contains(LogCode.historyExpiryFailed));
      store.failWrites = false;
      service.expiry.cleanUp();
      expect(store.inner.count, 1);
    });

    test('3 failed runs in a row show the banner; the next good run clears '
        'it', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      seed({'old': 2});
      store.failWrites = true;
      service = build(); // run 1
      service.expiry.cleanUp(); // run 2
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
      service.expiry.cleanUp(); // run 3
      expect(service.banners, contains(HistoryBanner.expiryFailed));
      service.expiry.cleanUp();
      expect(service.banners, contains(HistoryBanner.expiryFailed));
      store.failWrites = false;
      service.expiry.cleanUp();
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
    });

    test('a good run in between starts the count again', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.failWrites = true;
      service = build(); // 1
      service.expiry.cleanUp(); // 2
      store.failWrites = false;
      service.expiry.cleanUp(); // good
      store.failWrites = true;
      service.expiry.cleanUp(); // 1
      service.expiry.cleanUp(); // 2
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
    });
  });

  group('when the clean-up runs', () {
    test('every 15 minutes on the minute check', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      seed({'old': 2});
      for (var i = 0; i < 14; i++) {
        now += minute;
        service.expiry.check();
      }
      expect(store.inner.count, 1);
      now += minute;
      service.expiry.check();
      expect(store.inner.count, 0);
    });

    test('after a wake (the wall clock jumped past the check interval)', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      now += minute;
      service.expiry.check();
      seed({'old': 2});
      now += 3 * minute; // asleep
      service.expiry.check();
      expect(store.inner.count, 0);
    });

    test('after the clock was set back', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      now += minute;
      service.expiry.check();
      seed({'old': 2});
      now -= 10 * minute;
      service.expiry.check();
      expect(store.inner.count, 0);
    });
  });

  group('choosing a time', () {
    test('countRemovedBy: shorter counts the items it would newly delete; '
        'longer or Never is 0', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 2, 'b': 8, 'c': 20});
      service = build();
      expect(service.expiry.countRemovedBy(1), 3);
      expect(service.expiry.countRemovedBy(7), 2);
      expect(service.expiry.countRemovedBy(30), 0);
      expect(service.expiry.countRemovedBy(0), 0);
    });

    // Tester finding B2: the dialog's count is what Delete removes.
    test('countRemovedBy also counts expired items the clean-up has not '
        'removed yet, so it equals what setDays deletes', () {
      store.inner.writeSetting(historyExpirySetting, '7');
      service = build();
      seed({'waiting': 9, 'shown': 3, 'keep': 0});
      expect(service.expiry.countRemovedBy(1), 2);
      expect(service.expiry.countRemovedBy(7), 0, reason: 'not shorter');
      expect(service.expiry.setDays(1), 2);
      expect(store.inner.count, 1);
    });

    test('from Never, every older item counts', () {
      seed({'a': 2, 'b': 400});
      service = build();
      expect(service.expiry.countRemovedBy(1), 2);
    });

    test('countRemovedBy is null when the count cannot be read', () {
      store = FlakyStore(_ThrowingCountStore());
      service = build();
      expect(service.expiry.countRemovedBy(1), isNull);
    });

    test('a shorter time saves and deletes, and says how many', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 2, 'b': 8, 'keep': 0});
      service = build();
      expect(service.expiry.setDays(1), 2);
      expect(service.expiry.days, 1);
      expect(store.inner.readSetting(historyExpirySetting), '1');
      expect(texts(), ['keep']);
      expect(log.codes, contains(LogCode.historyExpired));
    });

    test('a longer time or Never saves and restores nothing', () {
      store.inner.writeSetting(historyExpirySetting, '1');
      seed({'a': 2});
      service = build();
      expect(store.inner.count, 0);
      seed({'b': 0});
      expect(service.expiry.setDays(30), 0);
      expect(service.expiry.setDays(0), 0);
      expect(service.expiry.days, 0);
      expect(texts(), ['b']);
    });

    test('a failed save keeps the old setting and logs settingSaveFailed', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      seed({'a': 8});
      service = build();
      store.failWrites = true;
      expect(service.expiry.setDays(7), isNull);
      expect(service.expiry.days, 30);
      expect(store.inner.readSetting(historyExpirySetting), '30');
      expect(store.inner.count, 1);
      expect(log.codes, contains(LogCode.settingSaveFailed));
    });

    test('only 0, 1, 7 and 30 are accepted', () {
      service = build();
      expect(() => service.expiry.setDays(2), throwsArgumentError);
    });

    test('memory only: applies in memory; the setting is not kept', () {
      store = FlakyStore(MemoryHistoryStore());
      seed({'a': 2});
      service = build(notices: {HistoryNotice.memoryOnly});
      expect(service.expiry.days, 0);
      expect(service.expiry.setDays(1), 1);
      expect(texts(), isEmpty);
    });

    test('a good save clears the clean-up warning', () {
      store.inner.writeSetting(historyExpirySetting, '30');
      store.failWrites = true;
      service = build();
      service.expiry.cleanUp();
      service.expiry.cleanUp();
      expect(service.banners, contains(HistoryBanner.expiryFailed));
      store.failWrites = false;
      service.expiry.setDays(1);
      expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
    });

    // Tester finding B1: any good save starts the failure count again, not
    // only one that deletes.
    for (final (from, to) in [(1, 7), (7, 30), (1, 0)]) {
      test('a good save from $from to $to days (nothing deleted) also clears '
          'the warning and starts the count again', () {
        store.inner.writeSetting(historyExpirySetting, '$from');
        store.failWrites = true;
        service = build();
        service.expiry.cleanUp();
        service.expiry.cleanUp();
        expect(service.expiry.failing, isTrue);
        store.failWrites = false;
        expect(service.expiry.setDays(to), 0);
        expect(service.expiry.failing, isFalse);
        expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
        if (to == 0) return;
        // Two more failed runs are not yet 3 in a row.
        store.failWrites = true;
        service.expiry.cleanUp();
        service.expiry.cleanUp();
        expect(service.banners, isNot(contains(HistoryBanner.expiryFailed)));
        service.expiry.cleanUp();
        expect(service.banners, contains(HistoryBanner.expiryFailed));
      });
    }
  });

  group('timers (only while ticking)', () {
    testWidgets('the list refreshes when its oldest item expires, between '
        'clean-ups (R1)', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.inner.insertOrBump('a', ClipKind.text, now - day + 30000);
      store.failWrites = true; // only the read filter can hide it
      service = build();
      service.expiry.startTicking(listenToLifecycle: false);
      service.expiry.cleanUp();
      expect(texts(), ['a']);
      now += 30001;
      await tester.pump(const Duration(milliseconds: 30001));
      expect(texts(), isEmpty);
      service.dispose();
    });

    // Reviewer F2: in the app's order (start, then startTicking from
    // main.dart) and with no clean-up in between, the item still leaves the
    // list at its cut-off.
    testWidgets('in the app\'s order the list refreshes when its oldest item '
        'expires, with no clean-up run', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.inner.insertOrBump('a', ClipKind.text, now - day + 2 * minute);
      service = build();
      service.expiry.startTicking(listenToLifecycle: false);
      expect(texts(), ['a']);
      for (var i = 0; i < 121; i++) {
        now += 1000;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(texts(), isEmpty);
      expect(store.inner.count, 1, reason: 'hidden by the filter, no clean-up');
      service.dispose();
    });

    // Reviewer F3: a list that can't be read must not keep an expired item
    // on screen, nor retry (and log) every second.
    testWidgets('reads that fail: expired items still leave the list, and '
        'the refresh is not retried every second', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      store.inner
        ..insertOrBump('a', ClipKind.text, now - day + 30000)
        ..insertOrBump('b', ClipKind.text, now - day + 45000)
        ..insertOrBump('fresh', ClipKind.text, now);
      service = build();
      service.expiry.startTicking(listenToLifecycle: false);
      expect(texts(), ['fresh', 'b', 'a']);
      store.failReads = true;
      for (var i = 0; i < 300; i++) {
        now += 1000;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(texts(), ['fresh']);
      final failures = log.codes.where((c) => c == LogCode.readFailed).length;
      expect(failures, inInclusiveRange(1, 5));
      service.dispose();
    });

    testWidgets('the minute check runs the clean-up after 15 minutes', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      service.expiry.startTicking(listenToLifecycle: false);
      seed({'old': 2});
      for (var i = 0; i < 14; i++) {
        now += minute;
        await tester.pump(const Duration(minutes: 1));
      }
      expect(store.inner.count, 1);
      now += minute;
      await tester.pump(const Duration(minutes: 1));
      expect(store.inner.count, 0);
      service.dispose();
    });

    // Reviewer F11: one handler for becoming active, not onShow and
    // onResume both.
    testWidgets('coming back from hidden runs one clean-up, not two', (
      tester,
    ) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      service = build();
      service.expiry.startTicking();
      store.failWrites = true; // each run logs historyExpiryFailed
      int runs() =>
          log.codes.where((c) => c == LogCode.historyExpiryFailed).length;
      final b = tester.binding;
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(runs(), 0);
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(runs(), 1);
      service.dispose();
    });

    testWidgets('no timer before startTicking', (tester) async {
      store.inner.writeSetting(historyExpirySetting, '1');
      seed({'a': 0});
      service = build();
      expect(service.expiry.ticking, isFalse);
      // A pending timer here would fail the test.
    });
  });

  test('snippets are never removed (R2)', () {
    store.inner.writeSetting(historyExpirySetting, '1');
    service = build();
    final before = service.snippets.items.length;
    service.expiry.setDays(1);
    service.expiry.cleanUp();
    expect(service.snippets.items.length, before);
  });

  test('cutoffFor: now minus the days, null for Never', () {
    expect(expiryCutoff(0, 10 * day), isNull);
    expect(expiryCutoff(1, 10 * day), 9 * day);
    expect(expiryCutoff(30, 100 * day), 70 * day);
  });
}

class _NoSettingStore extends MemoryHistoryStore {
  @override
  String? readSetting(String key) =>
      key == historyExpirySetting ? null : super.readSetting(key);
}

class _ThrowingReadStore extends MemoryHistoryStore {
  @override
  String? readSetting(String key) {
    if (key == historyExpirySetting) throw StateError('locked');
    return super.readSetting(key);
  }
}

/// The auto-delete setting can't be read while [fail] is set.
class _SometimesUnreadable extends MemoryHistoryStore {
  bool fail = true;

  @override
  String? readSetting(String key) {
    if (fail && key == historyExpirySetting) throw StateError('locked');
    return super.readSetting(key);
  }
}

class _ThrowingCountStore extends MemoryHistoryStore {
  @override
  int countOlderThan(int cutoffMs, {int? notBefore}) =>
      throw StateError('locked');
}
