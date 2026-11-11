// M1.7 tester: launch at login edge cases (docs/design/settings-and-expiry.md
// "Launch at login", R4 "the switch always shows what the OS really has",
// "Failure plan"). Fakes only: nothing here touches a real login item.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kusunga/log/app_log.dart';
import 'package:kusunga/settings/login_item.dart';

import '../support/fakes.dart';

/// A port with one answer for reads and one for changes, so a test can say
/// "the OS still has it on" after a failed change.
class _SplitPort implements LoginItemPort {
  LoginItemAnswer reads = const LoginItemAnswer(LoginItemState.off);
  LoginItemAnswer changes = const LoginItemAnswer(LoginItemState.off);
  int statusCalls = 0;
  int setCalls = 0;

  @override
  Future<LoginItemAnswer> status() async {
    statusCalls++;
    return reads;
  }

  @override
  Future<LoginItemAnswer> set(bool on) async {
    setCalls++;
    return changes;
  }

  @override
  Future<void> openSettings() async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('com.wnasoni.kusunga/login_item');

  late FakeLog log;
  setUp(() => log = FakeLog());

  group('the switch shows what the OS says (R4)', () {
    const expectedOn = {
      LoginItemState.on: true,
      LoginItemState.needsApproval: true, // "on" with a note (UI spec)
      LoginItemState.off: false,
      LoginItemState.failed: false,
      LoginItemState.unsupported: false,
      LoginItemState.turnedOffInTaskManager: false,
    };
    for (final from in LoginItemState.values) {
      for (final to in LoginItemState.values) {
        test('a read of $to after $from shows ${expectedOn[to]}', () async {
          final port = _SplitPort()..reads = LoginItemAnswer(from);
          final s = LoginItemService(port: port, log: log);
          await s.refresh();
          expect(s.isOn, expectedOn[from]);
          port.reads = LoginItemAnswer(to);
          await s.refresh();
          expect(s.isOn, expectedOn[to]);
          expect(s.state, to);
          s.dispose();
        });
      }
    }

    test('a read does not log, announce or call the change method', () async {
      final port = _SplitPort()
        ..reads = const LoginItemAnswer(LoginItemState.on);
      final s = LoginItemService(port: port, log: log);
      await s.refresh();
      expect(log.codes, isEmpty);
      expect(s.announcement, isNull);
      expect(s.announceSerial, 0);
      expect(port.setCalls, 0);
      s.dispose();
    });

    test(
      'turning on is refused on macOS 12 and the port is not called',
      () async {
        final port = _SplitPort()
          ..reads = const LoginItemAnswer(LoginItemState.unsupported);
        final s = LoginItemService(port: port, log: log);
        await s.refresh();
        await s.set(true);
        expect(port.setCalls, 0);
        expect(s.isOn, isFalse);
        expect(s.enabled, isFalse);
        s.dispose();
      },
    );

    test('a second change while one runs is ignored; a read in between is '
        'ignored too', () async {
      final port = FakeLoginItemPort();
      final s = LoginItemService(port: port, log: log);
      final held = port.hold();
      final first = s.set(true);
      await s.set(false);
      await s.refresh();
      expect(port.setCalls, [true]);
      expect(port.statusCalls, 0);
      expect(s.isOn, isTrue, reason: 'keeps its new position meanwhile');
      held.complete(const LoginItemAnswer(LoginItemState.on));
      await first;
      expect(s.isOn, isTrue);
      expect(log.codes, [LogCode.loginItemOn]);
      s.dispose();
    });

    test(
      'disposed while a change runs: no log and no notification after',
      () async {
        final port = FakeLoginItemPort();
        final s = LoginItemService(port: port, log: log);
        final held = port.hold();
        final pending = s.set(true);
        s.dispose();
        held.complete(const LoginItemAnswer(LoginItemState.on));
        await pending;
        expect(log.codes, isEmpty);
      },
    );

    test(
      'a failed TURN OFF re-reads the OS: if the item is still on, the '
      'switch is still on (it never shows off while the OS has it on)',
      () async {
        final port = _SplitPort()
          ..reads = const LoginItemAnswer(LoginItemState.on)
          ..changes = const LoginItemAnswer(LoginItemState.failed, error: 13);
        final s = LoginItemService(port: port, log: log);
        await s.refresh();
        expect(s.isOn, isTrue);
        await s.set(false);
        // The OS still says on.
        expect(s.isOn, isTrue);
        expect(log.codes, [LogCode.loginItemFailed]);
        expect(log.details, [13]);
        s.dispose();
      },
    );
  });

  group('the channel: failures and a native side that never answers', () {
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'openLoginItemsSettings: an error or no native side does not throw',
      () async {
        final port = ChannelLoginItemPort(channel: channel);
        await port.openSettings(); // no handler: MissingPluginException
        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'x');
        });
        await port.openSettings();
      },
    );

    test(
      'a reply with a path or other extra keys gives only the state',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => {
            'state': 'enabled',
            'path': '/Applications/Kusunga.app',
            'user': 'someone',
          },
        );
        final a = await ChannelLoginItemPort(channel: channel).status();
        expect(a.state, LoginItemState.on);
        expect(a.error, isNull);
      },
    );

    test('an error number that is not an int, or a state that is not a '
        'string, is a failure', () async {
      for (final reply in <Object?>[
        {'state': 'error', 'error': 1.5},
        {'state': null},
        <Object?, Object?>{},
        [1, 2],
        42,
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async => reply);
        final a = await ChannelLoginItemPort(channel: channel).set(true);
        expect(a.state, LoginItemState.failed, reason: '$reply');
        expect(a.error, isNull, reason: '$reply');
      }
    });

    testWidgets('a call that never returns does not freeze the switch for '
        'good: after a minute it is usable again and shows the failure', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final s = LoginItemService(
        port: ChannelLoginItemPort(channel: channel),
        log: log,
      );
      unawaited(s.set(true));
      await tester.pump();
      expect(s.busy, isTrue);
      await tester.pump(const Duration(minutes: 1));
      expect(s.busy, isFalse, reason: 'input is ignored while busy: forever');
      s.dispose();
    });
  });
}
