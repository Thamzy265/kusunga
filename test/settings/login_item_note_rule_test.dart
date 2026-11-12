// M1.7 tester, third pass (QA-M17-1, lead's ruling 2026-11-12): a failure
// note shows only after a change the user asked for has failed. A plain read
// that answers notFound or an error shows the switch off, with no note.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
const _failed = LoginItemAnswer(LoginItemState.failed);
const _turnOn = "Couldn't turn this on. Try again.";
const _turnOff = "Couldn't turn this off. Try again.";

void main() {
  late _Port port;
  late LoginItemService s;
  setUp(() {
    port = _Port();
    s = LoginItemService(port: port, log: FakeLog());
  });
  tearDown(() => s.dispose());

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

  group('a plain read that fails', () {
    test('at launch, any number of times: switch off, no note', () async {
      for (var i = 0; i < 3; i++) {
        await read(_failed);
        expect(s.isOn, isFalse);
        expect(s.note, isNull);
        expect(s.enabled, isTrue);
      }
    });

    test('after the switch was on: off, no note', () async {
      await read(_on);
      await read(_failed);
      expect(s.isOn, isFalse);
      expect(s.note, isNull);
    });

    test('then a failed turn-on: the note says "on"', () async {
      await read(_failed);
      await change(true, _failed, _failed);
      expect(s.isOn, isFalse);
      expect(s.note, _turnOn);
    });

    test('then a failed turn-on that the read shows off: "on" note', () async {
      await read(_failed);
      await change(true, _failed, _off);
      expect(s.note, _turnOn);
      expect(s.isOn, isFalse);
    });

    test('on, then a plain failed read, then a failed turn-off from a good '
        'read of on: the note says "off", switch on', () async {
      await read(_on);
      await read(_failed);
      await read(_on);
      await change(false, _failed, _failed);
      expect(s.isOn, isTrue);
      expect(s.note, _turnOff);
    });

    test('then a change that the OS answers notFound is a failed change, '
        'with its note', () async {
      await read(_failed);
      await change(true, _failed, _failed);
      expect(s.note, _turnOn);
    });

    test('then needs approval or Task Manager on a plain read: their own '
        'notes show', () async {
      await read(_failed);
      await read(const LoginItemAnswer(LoginItemState.needsApproval));
      expect(s.note, startsWith('Allow Kusunga'));
      expect(s.isOn, isTrue);
      await read(const LoginItemAnswer(LoginItemState.turnedOffInTaskManager));
      expect(s.note, 'Turned off in Task Manager.');
      await read(const LoginItemAnswer(LoginItemState.unsupported));
      expect(s.note, 'Needs macOS 13 or later.');
    });
  });

  group('after a failed change, plain reads', () {
    test('that fail keep the note until a read answers a real state', () async {
      await change(true, _failed, _failed);
      for (var i = 0; i < 3; i++) {
        await read(_failed);
        expect(s.note, _turnOn);
      }
      await read(_off);
      expect(s.note, isNull);
    });

    test('that answer needs approval or Task Manager show those notes, '
        'not the failure note', () async {
      await change(true, _failed, _failed);
      await read(const LoginItemAnswer(LoginItemState.needsApproval));
      expect(s.note, startsWith('Allow Kusunga'));
      await change(true, _failed, _failed);
      await read(const LoginItemAnswer(LoginItemState.turnedOffInTaskManager));
      expect(s.note, 'Turned off in Task Manager.');
    });

    test('a failed turn-off the re-read shows already off (the user got what '
        'they asked), then a plain failed read: the switch does not jump '
        'back on', () async {
      await read(_on);
      await change(false, _failed, _off);
      expect(s.isOn, isFalse);
      expect(s.note, isNull);
      await read(_failed);
      expect(
        s.isOn,
        isFalse,
        reason:
            'the OS said off; a later unreadable '
            'OS must not turn the switch on',
      );
      expect(s.note, isNull);
    });

    test('a failed turn-on the re-read shows already on (applied late), '
        'then a plain failed read: no stale "turn this on" note', () async {
      await change(true, _failed, _on);
      expect(s.isOn, isTrue);
      expect(s.note, isNull);
      await read(_failed);
      expect(s.note, isNull);
    });
  });

  group('during a change', () {
    test('a plain failed state before it shows no failure note while it '
        'runs', () async {
      await read(_failed);
      final c = Completer<LoginItemAnswer>();
      final gate = _GatePort(c.future);
      final svc = LoginItemService(port: gate, log: FakeLog());
      addTearDown(svc.dispose);
      await svc.refresh();
      final f = svc.set(true);
      expect(svc.isOn, isTrue);
      expect(svc.note, isNull);
      c.complete(_on);
      await f;
      expect(svc.note, isNull);
    });

    test('notFound answered to the change itself is logged as a failure '
        'and shown', () async {
      await change(true, _failed, _off);
      expect(s.note, _turnOn);
    });
  });
}

class _GatePort implements LoginItemPort {
  _GatePort(this.gate);
  final Future<LoginItemAnswer> gate;
  var first = true;
  @override
  Future<LoginItemAnswer> status() async {
    if (first) {
      first = false;
      return _failed;
    }
    return gate;
  }

  @override
  Future<LoginItemAnswer> set(bool on) => gate;
  @override
  Future<void> openSettings() async {}
}
