// M1.7 launch at login (docs/design/settings-and-expiry.md, "Launch at
// login"): the channel contract with LoginItemBridge.swift and
// login_item_bridge.cpp, and the service the Settings tab shows. The OS is the
// source of truth: nothing is stored by Kusunga.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/history/data_profile.dart';
import 'package:kusunga/history/pause_service.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';

import '../support/fakes.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/login_item');

  group('ChannelLoginItemPort', () {
    final calls = <MethodCall>[];
    Object? Function(MethodCall call) answer = (_) => null;

    setUp(() {
      calls.clear();
      answer = (_) => null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final result = answer(call);
        if (result is Exception) throw result;
        return result;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    ChannelLoginItemPort port() => ChannelLoginItemPort(channel: channel);

    test('loginItemStatus takes no arguments and maps every state', () async {
      const states = {
        'enabled': LoginItemState.on,
        'notRegistered': LoginItemState.off,
        'requiresApproval': LoginItemState.needsApproval,
        'notFound': LoginItemState.failed,
        'error': LoginItemState.failed,
        'unsupported': LoginItemState.unsupported,
        'disabledByUser': LoginItemState.turnedOffInTaskManager,
      };
      for (final MapEntry(key: name, value: state) in states.entries) {
        calls.clear();
        answer = (_) => {'state': name};
        final a = await port().status();
        expect(a.state, state, reason: name);
        expect(calls.single.method, 'loginItemStatus');
        expect(calls.single.arguments, isNull);
      }
    });

    test('setLoginItem sends only a bool and reads the error number', () async {
      answer = (_) => {'state': 'error', 'error': 5};
      final a = await port().set(true);
      expect(calls.single.method, 'setLoginItem');
      expect(calls.single.arguments, true);
      expect(a.state, LoginItemState.failed);
      expect(a.error, 5);
      calls.clear();
      answer = (_) => {'state': 'notRegistered'};
      expect((await port().set(false)).state, LoginItemState.off);
      expect(calls.single.arguments, false);
    });

    test('openLoginItemsSettings takes no arguments', () async {
      await port().openSettings();
      expect(calls.single.method, 'openLoginItemsSettings');
      expect(calls.single.arguments, isNull);
    });

    test('a bad reply, an error or no native side is a failure', () async {
      for (final reply in <Object?>[
        null,
        'enabled',
        {'state': 'weird'},
        {'state': 7},
        {'state': 'error', 'error': 'text'},
        PlatformException(code: 'x'),
        MissingPluginException(),
      ]) {
        answer = (_) => reply;
        final a = await port().status();
        expect(a.state, LoginItemState.failed, reason: '$reply');
        expect(a.error, isNull, reason: '$reply');
      }
    });
  });

  // Tester finding B4: a native call with no answer within the M1.6 limit
  // (2 s) has failed, so the switch is never stuck.
  group('a native side that does not answer (B4)', () {
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void hang({Object? Function(MethodCall call)? except}) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          final answer = except?.call(call);
          if (answer != null) return answer;
          return Completer<Object?>().future;
        });

    test('the limit is the native-call limit of M1.6, 2 seconds', () {
      expect(ChannelLoginItemPort.timeout, PauseService.nativeTimeout);
      expect(ChannelLoginItemPort.timeout, const Duration(seconds: 2));
    });

    testWidgets('loginItemStatus and setLoginItem fail at 2 s, not before', (
      tester,
    ) async {
      hang();
      final port = ChannelLoginItemPort(channel: channel);
      for (final call in [port.status, () => port.set(true)]) {
        LoginItemAnswer? got;
        unawaited(call().then((a) => got = a));
        await tester.pump(const Duration(milliseconds: 1999));
        expect(got, isNull);
        await tester.pump(const Duration(milliseconds: 1));
        expect(got?.state, LoginItemState.failed);
        expect(got?.error, isNull);
      }
    });

    testWidgets('a late answer after the limit is ignored', (tester) async {
      final reply = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) => reply.future);
      LoginItemAnswer? got;
      unawaited(
        ChannelLoginItemPort(channel: channel).set(true).then((a) => got = a),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(got?.state, LoginItemState.failed);
      reply.complete({'state': 'enabled'});
      await tester.pump();
      expect(got?.state, LoginItemState.failed);
    });

    testWidgets('openLoginItemsSettings returns at 2 s without throwing', (
      tester,
    ) async {
      hang();
      var done = false;
      unawaited(
        ChannelLoginItemPort(
          channel: channel,
        ).openSettings().then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 1999));
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });

    testWidgets('turning on with no answer: failed at 2 s, read again, '
        'usable at 4 s, off with "Couldn\'t turn this on"', (tester) async {
      hang();
      final log = FakeLog();
      final s = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: log,
      );
      unawaited(s.set(true));
      await tester.pump(const Duration(seconds: 2));
      expect(log.codes, [LogCode.loginItemFailed]);
      expect(log.details, [null]);
      expect(s.busy, isTrue, reason: 'the read after it is still running');
      await tester.pump(const Duration(seconds: 2));
      expect(s.busy, isFalse);
      expect(s.isOn, isFalse);
      expect(s.note, "Couldn't turn this on. Try again.");
      s.dispose();
    });

    testWidgets('turning off with no answer while the OS has it on: on, '
        'with "Couldn\'t turn this off"', (tester) async {
      hang(
        except: (call) =>
            call.method == 'loginItemStatus' ? {'state': 'enabled'} : null,
      );
      final s = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: FakeLog(),
      );
      await s.refresh();
      expect(s.isOn, isTrue);
      unawaited(s.set(false));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(s.busy, isFalse);
      expect(s.isOn, isTrue);
      expect(s.note, "Couldn't turn this off. Try again.");
      s.dispose();
    });
  });

  group('LoginItemService', () {
    late FakeLoginItemPort port;
    late FakeLog log;
    late LoginItemService service;

    setUp(() {
      port = FakeLoginItemPort();
      log = FakeLog();
      service = LoginItemService(port: port, log: log);
    });
    tearDown(() => service.dispose());

    test('starts off before the first read (AC2), and reads the OS', () async {
      expect(service.state, LoginItemState.off);
      expect(service.isOn, isFalse);
      port.next = const LoginItemAnswer(LoginItemState.on);
      await service.refresh();
      expect(service.state, LoginItemState.on);
      expect(service.isOn, isTrue);
      expect(port.statusCalls, 1);
    });

    test('turning on logs loginItemOn and announces', () async {
      port.next = const LoginItemAnswer(LoginItemState.on);
      await service.set(true);
      expect(port.setCalls, [true]);
      expect(service.isOn, isTrue);
      expect(log.codes, [LogCode.loginItemOn]);
      expect(service.announcement, 'Launch at login on');
    });

    test('turning off logs loginItemOff and announces', () async {
      port.next = const LoginItemAnswer(LoginItemState.off);
      await service.set(false);
      expect(log.codes, [LogCode.loginItemOff]);
      expect(service.announcement, 'Launch at login off');
    });

    test('a failure goes back off and logs the OS error number', () async {
      port.next = const LoginItemAnswer(LoginItemState.failed, error: 22);
      await service.set(true);
      expect(service.state, LoginItemState.failed);
      expect(service.isOn, isFalse);
      expect(log.codes, [LogCode.loginItemFailed]);
      expect(log.details, [22]);
      expect(service.note, "Couldn't turn this on. Try again.");
    });

    test('needs approval: on, with the note and the button', () async {
      port.next = const LoginItemAnswer(LoginItemState.needsApproval);
      await service.set(true);
      expect(service.isOn, isTrue);
      expect(service.showOpenLoginItems, isTrue);
      expect(log.codes, [LogCode.loginItemNeedsApproval]);
      expect(
        service.note,
        'Allow Kusunga in System Settings › General › Login Items.',
      );
      await service.openLoginItems();
      expect(port.openCalls, 1);
    });

    test(
      'Windows: turned off in Task Manager shows off with the note',
      () async {
        port.next = const LoginItemAnswer(
          LoginItemState.turnedOffInTaskManager,
        );
        await service.refresh();
        expect(service.isOn, isFalse);
        expect(service.enabled, isTrue);
        expect(service.note, 'Turned off in Task Manager.');
        expect(service.showOpenLoginItems, isFalse);
      },
    );

    test(
      'macOS 12: off and disabled, with the note; set does nothing',
      () async {
        port.next = const LoginItemAnswer(LoginItemState.unsupported);
        await service.refresh();
        expect(service.isOn, isFalse);
        expect(service.enabled, isFalse);
        expect(service.note, 'Needs macOS 13 or later.');
        await service.set(true);
        expect(port.setCalls, isEmpty);
      },
    );

    test('while the OS call runs the switch keeps its new position and '
        'other input is ignored', () async {
      final pending = port.hold();
      final first = service.set(true);
      expect(service.busy, isTrue);
      expect(service.isOn, isTrue);
      await service.set(false); // ignored
      await service.refresh(); // ignored
      expect(port.setCalls, [true]);
      expect(port.statusCalls, 0);
      pending.complete(const LoginItemAnswer(LoginItemState.on));
      await first;
      expect(service.busy, isFalse);
      expect(service.isOn, isTrue);
    });

    test("a read is not logged (only the user's changes are)", () async {
      for (final s in LoginItemState.values) {
        port.next = LoginItemAnswer(s, error: 3);
        await service.refresh();
        expect(service.state, s);
      }
      expect(log.codes, isEmpty);
      expect(service.announcement, isNull);
    });

    test('notFound or an error on a read: off with the failure note', () async {
      port.next = const LoginItemAnswer(LoginItemState.failed);
      await service.refresh();
      expect(service.isOn, isFalse);
      expect(service.note, "Couldn't turn this on. Try again.");
    });

    test('off and on have no note', () async {
      await service.refresh();
      expect(service.note, isNull);
      port.next = const LoginItemAnswer(LoginItemState.on);
      await service.refresh();
      expect(service.note, isNull);
    });

    test(
      'the switch shows what the OS says after a change elsewhere',
      () async {
        port.next = const LoginItemAnswer(LoginItemState.on);
        await service.set(true);
        port.next = const LoginItemAnswer(LoginItemState.off);
        await service.refresh();
        expect(service.isOn, isFalse);
      },
    );
  });

  // Tester finding B3 (R4, "truthful state"): after a failed change the
  // service reads the OS again and shows what it says.
  group('a failed change reads the OS again (B3)', () {
    late FakeLoginItemPort port;
    late FakeLog log;
    late LoginItemService service;

    const cantOn = "Couldn't turn this on. Try again.";
    const cantOff = "Couldn't turn this off. Try again.";

    setUp(() async {
      port = FakeLoginItemPort();
      log = FakeLog();
      service = LoginItemService(port: port, log: log);
    });
    tearDown(() => service.dispose());

    /// The OS has [state]; a change answers failed with error 13.
    Future<void> startAt(LoginItemState state) async {
      port.next = LoginItemAnswer(state);
      await service.refresh();
      port
        ..statusCalls = 0
        ..next = const LoginItemAnswer(LoginItemState.failed, error: 13);
    }

    test('a successful change is not read again', () async {
      port.next = const LoginItemAnswer(LoginItemState.on);
      await service.set(true);
      port.next = const LoginItemAnswer(LoginItemState.off);
      await service.set(false);
      expect(port.statusCalls, 0);
    });

    test('turn off fails, the OS still has it on: on, with "Couldn\'t turn '
        'this off"; logged once with the error of the change', () async {
      await startAt(LoginItemState.on);
      port.reads = const LoginItemAnswer(LoginItemState.on);
      await service.set(false);
      expect(port.statusCalls, 1);
      expect(service.state, LoginItemState.on);
      expect(service.isOn, isTrue);
      expect(service.note, cantOff);
      expect(service.busy, isFalse);
      expect(log.codes, [LogCode.loginItemFailed]);
      expect(log.details, [13]);
      expect(service.announcement, 'Launch at login on');
    });

    test('turn off fails, the OS has it off after all: off, no note', () async {
      await startAt(LoginItemState.on);
      port.reads = const LoginItemAnswer(LoginItemState.off);
      await service.set(false);
      expect(service.isOn, isFalse);
      expect(service.note, isNull);
      expect(service.announcement, 'Launch at login off');
    });

    test('turn off fails and the read fails too: the switch stays on '
        '(never off while the OS may have it on)', () async {
      await startAt(LoginItemState.on);
      port.reads = const LoginItemAnswer(LoginItemState.failed);
      await service.set(false);
      expect(service.state, LoginItemState.failed);
      expect(service.isOn, isTrue);
      expect(service.note, cantOff);
    });

    test('turn off fails from "needs approval": on, "Couldn\'t turn this '
        'off", and Open Login Items stays', () async {
      await startAt(LoginItemState.needsApproval);
      port.reads = const LoginItemAnswer(LoginItemState.needsApproval);
      await service.set(false);
      expect(service.isOn, isTrue);
      expect(service.note, cantOff);
      expect(service.showOpenLoginItems, isTrue);
    });

    test('Windows: turn off fails, Task Manager has it off: off, with '
        '"Turned off in Task Manager."', () async {
      await startAt(LoginItemState.on);
      port.reads = const LoginItemAnswer(LoginItemState.turnedOffInTaskManager);
      await service.set(false);
      expect(service.isOn, isFalse);
      expect(service.note, 'Turned off in Task Manager.');
    });

    test('turn on fails, the OS has it off: off, with "Couldn\'t turn this '
        'on"', () async {
      await startAt(LoginItemState.off);
      port.reads = const LoginItemAnswer(LoginItemState.off);
      await service.set(true);
      expect(service.state, LoginItemState.off);
      expect(service.isOn, isFalse);
      expect(service.note, cantOn);
      expect(service.announcement, 'Launch at login off');
    });

    test('turn on fails but the OS has it on: on, no note', () async {
      await startAt(LoginItemState.off);
      port.reads = const LoginItemAnswer(LoginItemState.on);
      await service.set(true);
      expect(service.isOn, isTrue);
      expect(service.note, isNull);
    });

    test('turn on fails and the OS needs approval: on, the approval note '
        'and Open Login Items', () async {
      await startAt(LoginItemState.off);
      port.reads = const LoginItemAnswer(LoginItemState.needsApproval);
      await service.set(true);
      expect(service.isOn, isTrue);
      expect(
        service.note,
        'Allow Kusunga in System Settings › General › Login Items.',
      );
      expect(service.showOpenLoginItems, isTrue);
    });

    test('the read is part of the change: input is ignored until it '
        'answers, and the switch keeps its new position', () async {
      await startAt(LoginItemState.on);
      final change = service.set(false);
      final read = port.hold(); // the read after the failed change
      await Future<void>.delayed(Duration.zero);
      expect(port.statusCalls, 1);
      expect(service.busy, isTrue);
      expect(service.isOn, isFalse);
      await service.set(true); // ignored
      await service.refresh(); // ignored
      expect(port.setCalls, [false]);
      expect(port.statusCalls, 1);
      read.complete(const LoginItemAnswer(LoginItemState.on));
      await change;
      expect(service.busy, isFalse);
      expect(service.isOn, isTrue);
      expect(service.note, cantOff);
    });

    test('disposed while the read runs: nothing changes after', () async {
      await startAt(LoginItemState.on);
      final change = service.set(false);
      final read = port.hold();
      await Future<void>.delayed(Duration.zero);
      var notified = 0;
      service.addListener(() => notified++);
      service.dispose();
      read.complete(const LoginItemAnswer(LoginItemState.on));
      await change;
      expect(notified, 0);
      expect(log.codes, [LogCode.loginItemFailed]);
    });

    test('a later read with a real state clears the failure note; a later '
        'read that fails keeps it', () async {
      await startAt(LoginItemState.on);
      port.reads = const LoginItemAnswer(LoginItemState.on);
      await service.set(false);
      port.reads = const LoginItemAnswer(LoginItemState.failed);
      await service.refresh();
      expect(service.isOn, isTrue);
      expect(service.note, cantOff);
      port.reads = const LoginItemAnswer(LoginItemState.on);
      await service.refresh();
      expect(service.isOn, isTrue);
      expect(service.note, isNull);
      port.reads = const LoginItemAnswer(LoginItemState.failed);
      await service.refresh();
      expect(service.isOn, isFalse, reason: 'an unreadable state shows off');
      expect(service.note, cantOn);
    });

    test('the next change starts without the old failure', () async {
      await startAt(LoginItemState.on);
      port.reads = const LoginItemAnswer(LoginItemState.on);
      await service.set(false);
      expect(service.note, cantOff);
      port
        ..reads = null
        ..next = const LoginItemAnswer(LoginItemState.off);
      await service.set(false);
      expect(service.isOn, isFalse);
      expect(service.note, isNull);
    });
  });

  test('Windows passes --login at a login start: it is not taken for a '
      'misspelled test profile switch (debug builds)', () {
    expect(dataProfileFrom(['--login'], debug: true), isA<NoDataProfile>());
    final both = dataProfileFrom([
      '--login',
      '-KusungaDataProfile',
      'qa',
    ], debug: true);
    expect(both, isA<ActiveDataProfile>());
  });
}
