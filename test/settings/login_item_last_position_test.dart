// M1.7 tester, fourth pass (P1, P2; PM ruling 2026-11-12): a plain read that
// answers notFound shows off with no note; one that errors or times out keeps
// the last position the OS reported in this run (off before any), with no
// note and no button; the first failing plain read in a row is logged;
// "where it was" wins while a failed change is kept.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';

import '../support/fakes.dart';

class _Port implements LoginItemPort {
  final queue = <LoginItemAnswer>[];
  @override
  Future<LoginItemAnswer> status() async => queue.removeAt(0);
  @override
  Future<LoginItemAnswer> set(bool on) async => queue.removeAt(0);
  @override
  Future<void> openSettings() async {}
}

const _on = LoginItemAnswer(LoginItemState.on);
const _off = LoginItemAnswer(LoginItemState.off);
const _approval = LoginItemAnswer(LoginItemState.needsApproval);
const _taskManager = LoginItemAnswer(LoginItemState.turnedOffInTaskManager);
const _unsupported = LoginItemAnswer(LoginItemState.unsupported);
const _notFound = LoginItemAnswer(
  LoginItemState.failed,
  failure: LoginItemFailure.notFound,
);
const _error = LoginItemAnswer(
  LoginItemState.failed,
  error: 5,
  failure: LoginItemFailure.error,
);
const _timeout = LoginItemAnswer(
  LoginItemState.failed,
  failure: LoginItemFailure.timeout,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/login_item');
  late _Port port;
  late FakeLog log;
  late LoginItemService s;
  setUp(() {
    port = _Port();
    log = FakeLog();
    s = LoginItemService(port: port, log: log);
  });
  tearDown(() {
    s.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> read(LoginItemAnswer a) async {
    port.queue.add(a);
    await s.refresh();
  }

  Future<void> change(bool on, LoginItemAnswer setAnswer, LoginItemAnswer re) {
    port.queue
      ..add(setAnswer)
      ..add(re);
    return s.set(on);
  }

  void quiet() {
    expect(s.note, isNull);
    expect(s.showOpenLoginItems, isFalse);
  }

  group('the last position the OS reported', () {
    test('an error or timeout before any real state: off, quiet', () async {
      await read(_error);
      expect(s.isOn, isFalse);
      quiet();
      await read(_timeout);
      expect(s.isOn, isFalse);
      quiet();
    });

    test('on, then error or timeout: stays on; notFound: off', () async {
      await read(_on);
      await read(_error);
      expect(s.isOn, isTrue);
      quiet();
      await read(_timeout);
      expect(s.isOn, isTrue);
      quiet();
      await read(_notFound);
      expect(s.isOn, isFalse);
      quiet();
      await read(_error);
      expect(s.isOn, isFalse, reason: 'notFound was the last OS report');
    });

    test('needs approval then an error: on, with neither the note nor the '
        'Open Login Items button (it is not a fresh answer)', () async {
      await read(_approval);
      expect(s.showOpenLoginItems, isTrue);
      await read(_error);
      expect(s.isOn, isTrue);
      quiet();
    });

    test('Task Manager off then an error: off, quiet', () async {
      await read(_on);
      await read(_taskManager);
      await read(_error);
      expect(s.isOn, isFalse);
      quiet();
    });

    test('off then an error stays off; on, off, error stays off', () async {
      await read(_on);
      await read(_off);
      await read(_timeout);
      expect(s.isOn, isFalse);
      quiet();
    });

    test('macOS 12 then an error read: the switch is not turned on', () async {
      await read(_unsupported);
      await read(_error);
      expect(s.isOn, isFalse);
      expect(s.note, isNull);
    });

    test('a successful change counts as the OS report', () async {
      port.queue.add(_on);
      await s.set(true);
      await read(_error);
      expect(s.isOn, isTrue);
      quiet();
      port.queue.add(_off);
      await s.set(false);
      await read(_timeout);
      expect(s.isOn, isFalse);
    });

    test('where it was wins while a failed change is kept: failed turn-off '
        'from on, then error reads: on with the turn-off note', () async {
      await read(_on);
      await change(false, _error, _timeout);
      expect(s.isOn, isTrue);
      expect(s.note, "Couldn't turn this off. Try again.");
      await read(_error);
      expect(s.isOn, isTrue);
      expect(s.note, "Couldn't turn this off. Try again.");
      await read(_notFound);
      expect(s.isOn, isTrue, reason: 'where it was, not the notFound rule');
      expect(s.note, "Couldn't turn this off. Try again.");
    });

    test('failed turn-on after an on report: off (where it was), turn-on '
        'note, even though the last report was on', () async {
      await read(_on);
      await read(_off);
      await change(true, _error, _error);
      expect(s.isOn, isFalse);
      expect(s.note, "Couldn't turn this on. Try again.");
      await read(_timeout);
      expect(s.isOn, isFalse);
    });

    test('a real read after a failed change ends it; a later error read '
        'follows the last position again', () async {
      await change(false, _error, _error);
      await read(_on);
      expect(s.note, isNull);
      await read(_error);
      expect(s.isOn, isTrue);
      quiet();
    });
  });

  group('logging a failing plain read', () {
    int failed() => log.codes.where((c) => c == LogCode.loginItemFailed).length;

    test('the first in a row is logged with its number (none for notFound '
        'or a timeout); the rest of the row is not', () async {
      await read(_error);
      expect(failed(), 1);
      expect(log.details.last, 5);
      await read(_timeout);
      await read(_notFound);
      expect(failed(), 1);
    });

    test('notFound and a timeout carry no number', () async {
      await read(_notFound);
      expect(log.details, [null]);
      await read(_off);
      await read(_timeout);
      expect(log.details, [null, null]);
    });

    test('a real state starts the count again: fail, ok, fail, fail, ok, '
        'fail logs 3', () async {
      for (final a in [_error, _off, _error, _error, _on, _timeout]) {
        await read(a);
      }
      expect(failed(), 3);
    });

    test('every real state starts it again (approval, Task Manager, '
        'unsupported)', () async {
      for (final real in [_approval, _taskManager, _unsupported, _on, _off]) {
        await read(_error);
        await read(real);
      }
      expect(failed(), 5);
    });

    test('a failed change logs once; its own re-read is not logged again, '
        'even when it fails too', () async {
      await change(true, _error, _timeout);
      expect(failed(), 1);
      await change(false, _notFound, _off);
      expect(failed(), 2);
    });

    test('plain reads of a failure do not log a user change or an '
        'announcement', () async {
      await read(_error);
      expect(log.codes, [LogCode.loginItemFailed]);
      expect(s.announceSerial, 0);
      expect(s.announcement, isNull);
    });
  });

  group('the channel: reasons from replies', () {
    Future<LoginItemAnswer> ask(Object? reply) async {
      messenger.setMockMethodCallHandler(channel, (call) async => reply);
      return ChannelLoginItemPort(channel: channel).status();
    }

    test('notFound and error replies give their reasons', () async {
      expect(
        (await ask({'state': 'notFound'})).failure,
        LoginItemFailure.notFound,
      );
      expect(
        (await ask({'state': 'error', 'error': 7})).failure,
        LoginItemFailure.error,
      );
      expect(
        (await ask({'state': 'error'})).failure,
        LoginItemFailure.error,
        reason: 'an error is an error even with no number',
      );
    });

    test('notFound that carries a number still is notFound and logs the '
        'number', () async {
      final a = await ask({'state': 'notFound', 'error': 3});
      expect(a.failure, LoginItemFailure.notFound);
      expect(a.error, 3);
    });

    test('bad replies are errors, never notFound (they must not hide '
        'behind the quiet off)', () async {
      for (final reply in <Object?>[
        null,
        'enabled',
        42,
        [1],
        <Object?, Object?>{},
        {'state': 'weird'},
        {'state': 7},
        {'state': 'enabled', 'error': 'x'},
        {'state': 'error', 'error': 1.5},
      ]) {
        final a = await ask(reply);
        expect(a.state, LoginItemState.failed, reason: '$reply');
        expect(a.failure, LoginItemFailure.error, reason: '$reply');
      }
    });

    test('no native side and a PlatformException are errors', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        (await ChannelLoginItemPort(channel: channel).status()).failure,
        LoginItemFailure.error,
      );
      messenger.setMockMethodCallHandler(channel, (c) async {
        throw PlatformException(code: 'x');
      });
      expect(
        (await ChannelLoginItemPort(channel: channel).status()).failure,
        LoginItemFailure.error,
      );
    });

    test('a good state has no failure reason', () async {
      for (final name in [
        'enabled',
        'notRegistered',
        'requiresApproval',
        'unsupported',
        'disabledByUser',
      ]) {
        expect((await ask({'state': name})).failure, isNull, reason: name);
      }
    });

    test('an answer with no reason: a number means error, none means '
        'notFound', () {
      expect(
        const LoginItemAnswer(LoginItemState.failed, error: 1).failure,
        LoginItemFailure.error,
      );
      expect(
        const LoginItemAnswer(LoginItemState.failed).failure,
        LoginItemFailure.notFound,
      );
      expect(
        const LoginItemAnswer(LoginItemState.on, error: 1).failure,
        isNull,
      );
    });

    testWidgets('timeouts during tab opens keep the last position and log '
        'once', (tester) async {
      final svc = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: log,
      );
      addTearDown(svc.dispose);
      messenger.setMockMethodCallHandler(
        channel,
        (c) async => {'state': 'enabled'},
      );
      await svc.refresh();
      expect(svc.isOn, isTrue);
      messenger.setMockMethodCallHandler(
        channel,
        (c) => Completer<Object?>().future,
      );
      for (var i = 0; i < 3; i++) {
        final f = svc.refresh(); // each tab open
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        await f;
        expect(svc.isOn, isTrue);
        expect(svc.note, isNull);
      }
      expect(log.codes.where((c) => c == LogCode.loginItemFailed).length, 1);
      expect(log.details, [null]);
    });

    testWidgets('two reads at once, one slow (times out) and one real: the '
        'real answer is not overwritten into a different position', (
      tester,
    ) async {
      final svc = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: log,
      );
      addTearDown(svc.dispose);
      var n = 0;
      messenger.setMockMethodCallHandler(channel, (c) {
        n++;
        if (n == 1) return Completer<Object?>().future;
        return Future.value({'state': 'enabled'});
      });
      final slow = svc.refresh();
      final fast = svc.refresh();
      await tester.pump();
      await fast;
      expect(svc.isOn, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await slow;
      expect(
        svc.isOn,
        isTrue,
        reason:
            'the timed-out read keeps what the '
            'OS last reported',
      );
      expect(svc.note, isNull);
    });
  });
}
