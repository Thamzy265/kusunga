// M1.7 tester, second pass: the re-read after a failed change, the failure
// note rules, the 2 s call limit and its boundary, a change applied late,
// dispose and input during the re-read.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';

import '../support/fakes.dart';

/// Every call waits for the test to answer it, in order.
class _ScriptedPort implements LoginItemPort {
  final calls = <String>[];
  final pending = <Completer<LoginItemAnswer>>[];

  Future<LoginItemAnswer> _next(String name) {
    calls.add(name);
    final c = Completer<LoginItemAnswer>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<LoginItemAnswer> status() => _next('status');
  @override
  Future<LoginItemAnswer> set(bool on) => _next('set($on)');
  @override
  Future<void> openSettings() async {}

  void answer(int i, LoginItemState s, {int? error}) =>
      pending[i].complete(LoginItemAnswer(s, error: error));
}

const _turnOn = "Couldn't turn this on. Try again.";
const _turnOff = "Couldn't turn this off. Try again.";

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/login_item');
  late FakeLog log;
  late _ScriptedPort port;
  late LoginItemService s;

  setUp(() {
    log = FakeLog();
    port = _ScriptedPort();
    s = LoginItemService(port: port, log: log);
  });
  tearDown(() {
    s.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> getOn() async {
    final f = s.refresh();
    port.answer(0, LoginItemState.on);
    await f;
    port.calls.clear();
    port.pending.clear();
  }

  group('a failed turn-off', () {
    test('and the read fails too: the switch stays on, with the turn-off '
        'note', () async {
      await getOn();
      final f = s.set(false);
      port.answer(0, LoginItemState.failed, error: 13);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.failed);
      await f;
      expect(port.calls, ['set(false)', 'status']);
      expect(s.isOn, isTrue);
      expect(s.note, _turnOff);
      expect(s.busy, isFalse);
      expect(log.codes, [LogCode.loginItemFailed]);
      expect(log.details, [13]);
    });

    test('and the read says off: the switch is off and there is no note '
        '(it is where the user asked)', () async {
      await getOn();
      final f = s.set(false);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.off);
      await f;
      expect(s.isOn, isFalse);
      expect(s.note, isNull);
    });

    test('and the read says on: the switch is on and says so', () async {
      await getOn();
      final f = s.set(false);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.on);
      await f;
      expect(s.isOn, isTrue);
      expect(s.note, _turnOff);
    });

    test('and the read needs approval (still on): turn-off note, button '
        'stays', () async {
      await getOn();
      final f = s.set(false);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.needsApproval);
      await f;
      expect(s.isOn, isTrue);
      expect(s.note, _turnOff);
      expect(s.showOpenLoginItems, isTrue);
    });

    test('the note goes when a later read answers for itself, and a later '
        'read that fails keeps it', () async {
      await getOn();
      var f = s.set(false);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.failed);
      await f;
      port.calls.clear();
      port.pending.clear();
      f = s.refresh();
      port.answer(0, LoginItemState.failed);
      await f;
      expect(s.isOn, isTrue, reason: 'still not off while unreadable');
      expect(s.note, _turnOff);
      port.pending.clear();
      f = s.refresh();
      port.answer(0, LoginItemState.off);
      await f;
      expect(s.isOn, isFalse);
      expect(s.note, isNull);
    });

    test(
      'the next change starts clean: a good turn-off clears the note',
      () async {
        await getOn();
        var f = s.set(false);
        port.answer(0, LoginItemState.failed);
        await Future<void>.delayed(Duration.zero);
        port.answer(1, LoginItemState.failed);
        await f;
        port.pending.clear();
        f = s.set(false);
        expect(s.note, isNull, reason: 'cleared when the new change starts');
        port.answer(0, LoginItemState.off);
        await f;
        expect(s.isOn, isFalse);
        expect(s.note, isNull);
      },
    );

    test(
      'input is ignored during the re-read, and a refresh in it too',
      () async {
        await getOn();
        final f = s.set(false);
        port.answer(0, LoginItemState.failed);
        await Future<void>.delayed(Duration.zero);
        expect(s.busy, isTrue, reason: 'the re-read is part of the change');
        await s.set(true);
        await s.refresh();
        expect(port.calls, ['set(false)', 'status']);
        expect(s.isOn, isFalse, reason: 'keeps the position it was asked for');
        port.answer(1, LoginItemState.on);
        await f;
        expect(s.busy, isFalse);
        expect(s.isOn, isTrue);
      },
    );

    test('disposed during the re-read: no exception, nothing logged or '
        'announced after', () async {
      await getOn();
      final f = s.set(false);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      s.dispose();
      port.answer(1, LoginItemState.off);
      await f;
      expect(s.announceSerial, 0);
      expect(log.codes, [LogCode.loginItemFailed]);
    });

    test('disposed while the change itself runs: no re-read is made', () async {
      await getOn();
      final f = s.set(false);
      s.dispose();
      port.answer(0, LoginItemState.failed);
      await f;
      expect(port.calls, ['set(false)']);
      expect(log.codes, isEmpty);
    });
  });

  group('a failed turn-on', () {
    test('read says off: off with the turn-on note', () async {
      final f = s.set(true);
      port.answer(0, LoginItemState.failed, error: 5);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.off);
      await f;
      expect(s.isOn, isFalse);
      expect(s.note, _turnOn);
    });

    test('the read also fails: off (never on), the turn-on note', () async {
      final f = s.set(true);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.failed);
      await f;
      expect(s.isOn, isFalse);
      expect(s.note, _turnOn);
    });

    test('applied late: the read says on, so the switch is on with no '
        'note', () async {
      final f = s.set(true);
      port.answer(0, LoginItemState.failed); // timed out
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.on); // but it was applied
      await f;
      expect(s.isOn, isTrue);
      expect(s.note, isNull);
    });

    test(
      'macOS 12 (unsupported) never shows a failure note over its own',
      () async {
        final f = s.set(true);
        port.answer(0, LoginItemState.failed);
        await Future<void>.delayed(Duration.zero);
        port.answer(1, LoginItemState.unsupported);
        await f;
        expect(s.note, 'Needs macOS 13 or later.');
        expect(s.isOn, isFalse);
      },
    );

    test('a read that turns out Task Manager off: the Task Manager note is '
        'not replaced when the user asked for off', () async {
      await getOn();
      final f = s.set(false);
      port.answer(0, LoginItemState.failed);
      await Future<void>.delayed(Duration.zero);
      port.answer(1, LoginItemState.turnedOffInTaskManager);
      await f;
      expect(s.isOn, isFalse);
      expect(s.note, 'Turned off in Task Manager.');
    });
  });

  group('the 2 second limit (channel)', () {
    Future<void> handler(
      WidgetTester tester,
      Duration set,
      Duration status,
      String statusState,
    ) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setLoginItem') {
          await Future<void>.delayed(set);
          return {'state': 'enabled'};
        }
        await Future<void>.delayed(status);
        return {'state': statusState};
      });
    }

    testWidgets('an answer at 1999 ms counts; one at 2001 ms is a failure', (
      tester,
    ) async {
      final port = ChannelLoginItemPort(channel: channel);
      await handler(
        tester,
        const Duration(milliseconds: 1999),
        const Duration(milliseconds: 2001),
        'enabled',
      );
      final a = port.set(true);
      await tester.pump(const Duration(milliseconds: 1999));
      expect((await a).state, LoginItemState.on);
      final b = port.status();
      await tester.pump(const Duration(milliseconds: 2001));
      expect((await b).state, LoginItemState.failed);
    });

    testWidgets('a late answer after the limit is ignored: it changes '
        'nothing and throws nothing', (tester) async {
      final port = ChannelLoginItemPort(channel: channel);
      await handler(tester, const Duration(seconds: 5), Duration.zero, 'off');
      final a = port.set(true);
      await tester.pump(const Duration(seconds: 2));
      expect((await a).state, LoginItemState.failed);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a set that times out but is applied late: the re-read shows '
        'on, no failure note', (tester) async {
      final service = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: log,
      );
      addTearDown(service.dispose);
      await handler(
        tester,
        const Duration(seconds: 3),
        Duration.zero,
        'enabled',
      );
      final f = service.set(true);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await f;
      expect(service.isOn, isTrue);
      expect(service.note, isNull);
      expect(service.busy, isFalse);
      expect(log.codes, [LogCode.loginItemFailed]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a turn-off where both the set and the re-read hang: freed '
        'after about 4 s, still on, with the turn-off note', (tester) async {
      final service = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: log,
      );
      addTearDown(service.dispose);
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      // Start from "on".
      messenger.setMockMethodCallHandler(channel, (call) async {
        return {'state': 'enabled'};
      });
      await service.refresh();
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final f = service.set(false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await f;
      expect(service.busy, isFalse);
      expect(service.isOn, isTrue);
      expect(service.note, _turnOff);
    });
  });
}
