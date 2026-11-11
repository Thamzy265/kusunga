// M1.7 launch at login (docs/design/settings-and-expiry.md, "Launch at
// login"): the channel contract with LoginItemBridge.swift and
// login_item_bridge.cpp, and the service the Settings tab shows. The OS is the
// source of truth: nothing is stored by Kusunga.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
